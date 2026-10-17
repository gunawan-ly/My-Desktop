#!/usr/bin/env bash
# Expose Kasm Web UI via link publik Cloudflare Tunnel (quick tunnel).
# Dipakai oleh workflow .github/workflows/kasm-workspace.yml
# Lebih cepat dari Tailscale untuk akses browser (routing via edge Jakarta).
#
# Catatan keamanan: URL publik bisa dibuka siapa saja yang tahu linknya,
# tapi login Kasm tetap wajib. URL acak tiap run dan hanya hidup
# selama runner jalan.
set -uo pipefail

log() { printf '[cf-tunnel] %s\n' "$*"; }
fail() { log "FATAL: $*"; exit 1; }

CLOUDFLARED_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"

# Download cloudflared
if [ ! -x /tmp/cloudflared ]; then
  log "Download cloudflared..."
  curl -fSL --max-time 120 -o /tmp/cloudflared "$CLOUDFLARED_URL" \
    || fail "Download cloudflared gagal."
  chmod +x /tmp/cloudflared
  log "cloudflared: $(/tmp/cloudflared --version 2>&1 | head -1)"
fi

# Bersihkan tunnel lama kalau ada
pkill -f "cloudflared tunnel" 2>/dev/null || true
sleep 2
rm -f /tmp/cloudflared.log

# Start tunnel ke Kasm (self-signed cert -> perlu --no-tls-verify)
log "Start tunnel ke https://127.0.0.1:443 ..."
nohup /tmp/cloudflared tunnel --url https://127.0.0.1:443 --no-tls-verify \
  > /tmp/cloudflared.log 2>&1 &
log "cloudflared pid $!"

# Tunggu URL muncul (maks ~60 detik)
log "Menunggu URL tunnel..."
for _ in $(seq 1 12); do
  sleep 5
  URL=$(grep -oE "https://[A-Za-z0-9.-]+\.trycloudflare\.com" \
    /tmp/cloudflared.log 2>/dev/null | head -1)
  if [ -n "$URL" ]; then
    log "Tunnel URL: $URL"
    [ -n "${GITHUB_ENV:-}" ] && echo "CF_TUNNEL_URL=$URL" >> "$GITHUB_ENV"
    if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
      {
        echo ""
        echo "### Akses Publik (Cloudflare Tunnel)"
        echo ""
        echo "URL: $URL"
        echo ""
        echo "Lebih cepat dari via Tailscale untuk akses browser."
        echo "Tetap butuh login Kasm seperti biasa."
      } >> "$GITHUB_STEP_SUMMARY"
    fi
    echo ""
    echo "===================================================================="
    echo " KASM PUBLIC LINK:"
    echo " $URL"
    echo "===================================================================="
    exit 0
  fi
  # Kalau proses mati, gagal cepat
  pgrep -f "cloudflared tunnel" > /dev/null 2>&1 || break
done

log "Gagal mendapatkan URL tunnel. Isi log:"
tail -n 20 /tmp/cloudflared.log 2>/dev/null || true
fail "Cloudflare Tunnel gagal start."
