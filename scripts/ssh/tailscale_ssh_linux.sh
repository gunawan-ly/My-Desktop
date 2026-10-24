#!/usr/bin/env bash
# Setup Tailscale + SSH server di GitHub-hosted Ubuntu runner.
# Dipakai oleh workflow .github/workflows/ssh-access-linux.yml
# untuk ngetes (mis. instalasi Kasm Workspaces) via SSH lewat Tailscale.
set -uo pipefail

TAILSCALE_AUTHKEY="${TAILSCALE_AUTHKEY:-}"
TS_HOSTNAME="${TS_HOSTNAME:-linux-runner}"
SSH_PUBLIC_KEY="${SSH_PUBLIC_KEY:-}"
LINUX_USER_PASSWORD="${LINUX_USER_PASSWORD:-}"

log() { printf '[tailscale-ssh-linux] %s\n' "$*"; }

install_tailscale() {
  if command -v tailscale >/dev/null 2>&1; then
    log "tailscale CLI sudah terinstall."
    return 0
  fi
  log "Install Tailscale (install.sh resmi)..."
  curl -fsSL https://tailscale.com/install.sh | sudo sh
  command -v tailscale >/dev/null 2>&1 || {
    log "Install Tailscale gagal."
    return 1
  }
  log "tailscale CLI terinstall."
}

join_tailnet() {
  log "tailscale up ($TS_HOSTNAME)..."
  sudo tailscale up --authkey="$TAILSCALE_AUTHKEY" --hostname="$TS_HOSTNAME" || {
    log "tailscale up gagal; status:"
    sudo tailscale status 2>&1 | sed 's/^/  /' || true
    return 1
  }
  log "tailscale up OK."
}

enable_ssh() {
  local USER_NAME
  USER_NAME="$(id -un)"

  if ! dpkg -s openssh-server >/dev/null 2>&1; then
    log "Install openssh-server..."
    sudo apt-get update -qq
    sudo apt-get install -y -qq openssh-server
  fi

  log "Menjalankan sshd..."
  sudo mkdir -p /run/sshd
  sudo service ssh start >/dev/null 2>&1 || sudo /usr/sbin/sshd >/dev/null 2>&1 || true
  sleep 2
  pgrep -f 'sshd' >/dev/null 2>&1 || {
    log "sshd tidak berjalan."
    return 1
  }

  # Login dengan public key (paling andal).
  if [ -n "$SSH_PUBLIC_KEY" ]; then
    log "Memasang SSH public key ke $USER_NAME..."
    install -d -m 700 "$HOME/.ssh"
    {
      printf '%s\n' "$SSH_PUBLIC_KEY"
      [ -f "$HOME/.ssh/authorized_keys" ] && cat "$HOME/.ssh/authorized_keys"
    } | awk 'NF && !seen[$0]++' > "$HOME/.ssh/authorized_keys"
    chmod 600 "$HOME/.ssh/authorized_keys"
    log "Public key terpasang."
    log "Fingerprint authorized_keys: $(ssh-keygen -l -f "$HOME/.ssh/authorized_keys" 2>/dev/null | head -n1 || echo n/a)"
  fi

  # Login dengan password (bila LINUX_USER_PASSWORD terisi).
  if [ -n "$LINUX_USER_PASSWORD" ]; then
    log "Mengatur password akun $USER_NAME..."
    printf '%s:%s\n' "$USER_NAME" "$LINUX_USER_PASSWORD" | sudo chpasswd \
      || log "Peringatan: pengaturan password gagal."
    log "Mengaktifkan PasswordAuthentication di sshd..."
    printf '%s\n' 'PasswordAuthentication yes' 'KbdInteractiveAuthentication yes' \
      | sudo tee /etc/ssh/sshd_config.d/01-password-auth.conf >/dev/null
    sudo service ssh restart >/dev/null 2>&1 || sudo /usr/sbin/sshd >/dev/null 2>&1 || true
    sleep 2
    pgrep -f 'sshd' >/dev/null 2>&1 || log "Peringatan: sshd tidak terdeteksi setelah restart."
  fi

  log "SSH aktif untuk user $USER_NAME."
}

main() {
  if [ -z "$TAILSCALE_AUTHKEY" ]; then
    log "TAILSCALE_AUTHKEY kosong; hentikan."
    exit 1
  fi

  install_tailscale || exit 1
  join_tailnet || exit 1

  local TSIP
  TSIP="$(sudo tailscale ip -4 2>/dev/null | head -n1 | tr -d '[:space:]')"
  if [ -z "$TSIP" ]; then
    log "Tidak dapat IP tailscale."
    echo "::warning::tailscale ip -4 kosong"
  else
    log "Tailscale IP: $TSIP"
    [ -n "${GITHUB_ENV:-}" ] && echo "TSIP=$TSIP" >> "$GITHUB_ENV"
  fi

  enable_ssh || exit 1

  echo ""
  echo "===================================================================="
  echo " SSH LINUX READY"
  echo ""
  echo "   ssh $(id -un)@${TSIP:-<ip-tailscale>}"
  echo ""
  if [ -n "$SSH_PUBLIC_KEY" ]; then
    echo "   Auth : public key (~/.ssh/id_*.pub) milik pemilik secret SSH_PUBLIC_KEY"
  fi
  if [ -n "$LINUX_USER_PASSWORD" ]; then
    echo "   Auth : password akun $(id -un) (terpasang dari workflow)"
  fi
  echo "   Catat: perangkat kamu harus join ke TAILNET yang sama."
  echo "===================================================================="
}

main "$@"
