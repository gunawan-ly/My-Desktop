#!/usr/bin/env bash
# Setup Kasm Workspaces di GitHub-hosted Ubuntu runner.
# Dipakai oleh workflow .github/workflows/kasm-workspace.yml
#
# Alur:
#   1. Download installer Kasm -> verifikasi SHA256 -> ekstrak
#   2. Install Kasm (background, tunggu sampai selesai)
#   3. (Opsional) Build image custom Ubuntu + OBS Studio
#   4. Daftarkan workspace baru ke database Kasm + group All Users
#   5. Reset password admin & user via database
#   6. Verifikasi login via API
#
# Env yang dipakai:
#   KASM_DOWNLOAD_URL, KASM_SHA256, KASM_IMAGE_TAG,
#   INSTALL_OBS, KASM_ADMIN_PASSWORD, KASM_USER_PASSWORD
set -uo pipefail

KASM_DOWNLOAD_URL="${KASM_DOWNLOAD_URL:-https://kasm-static-content.s3.amazonaws.com/kasm_release_1.17.0.7f020d.tar.gz}"
KASM_SHA256="${KASM_SHA256:-22a293ea52b2adb7f3f72a2de8e9be799f443b9da040e066df403478da77f62d}"
KASM_IMAGE_TAG="${KASM_IMAGE_TAG:-1.17.0}"
INSTALL_OBS="${INSTALL_OBS:-true}"
KASM_ADMIN_PASSWORD="${KASM_ADMIN_PASSWORD:-}"
KASM_USER_PASSWORD="${KASM_USER_PASSWORD:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="/tmp/kasm-setup"
INSTALL_TIMEOUT_SEC=2700  # 45 menit

log() { printf '[kasm-setup] %s\n' "$*"; }
fail() { log "FATAL: $*"; exit 1; }

# ---------------------------------------------------------------- download
download_kasm() {
  local tarball="$WORK_DIR/$(basename "$KASM_DOWNLOAD_URL")"
  mkdir -p "$WORK_DIR"
  cd "$WORK_DIR"

  if [ ! -f "$tarball" ]; then
    log "Download $KASM_DOWNLOAD_URL ..."
    curl -fSL -o "$tarball" "$KASM_DOWNLOAD_URL" || fail "Download gagal."
  else
    log "Tarball sudah ada, pakai ulang."
  fi

  if [ -n "$KASM_SHA256" ]; then
    log "Verifikasi SHA256..."
    echo "$KASM_SHA256  $(basename "$tarball")" | sha256sum -c - \
      || fail "SHA256 tidak cocok."
    log "SHA256 OK."
  else
    log "Peringatan: KASM_SHA256 kosong, lewati verifikasi."
  fi

  log "Ekstrak..."
  tar -xf "$tarball" || fail "Ekstrak gagal."
  [ -f "$WORK_DIR/kasm_release/install.sh" ] || fail "install.sh tidak ditemukan."
}

# ---------------------------------------------------------------- install
install_kasm() {
  cd "$WORK_DIR"
  log "Install Kasm (background, -e -W -J 4096)..."
  # Hapus log lama biar deteksi selesai tidak keliru.
  sudo rm -f /tmp/kasm_install.log /tmp/kasm_install_*.log
  nohup sudo bash kasm_release/install.sh -e -W -J 4096 \
    > /tmp/kasm_install.log 2>&1 &
  local elapsed=0
  while [ $elapsed -lt $INSTALL_TIMEOUT_SEC ]; do
    sleep 30
    elapsed=$((elapsed + 30))
    if ! pgrep -f "kasm_release/install.sh" > /dev/null 2>&1; then
      # Installer selesai. Sukses = file log bertimestamp terhapus otomatis.
      if ls /tmp/kasm_install_*.log > /dev/null 2>&1; then
        log "Installer berhenti tapi log timestamp masih ada:"
        tail -n 30 /tmp/kasm_install.log || true
        fail "Install Kasm gagal (lihat /tmp/kasm_install.log)."
      fi
      log "Install Kasm selesai (${elapsed}s)."
      return 0
    fi
    log "Masih install... (${elapsed}s)"
  done
  fail "Install Kasm timeout ${INSTALL_TIMEOUT_SEC}s."
}

# ---------------------------------------------------------------- db helper
db_pass() {
  sudo grep -oP 'POSTGRES_PASSWORD: "\K[^"]+' \
    /opt/kasm/current/docker/docker-compose.yaml 2>/dev/null \
    || fail "Tidak dapat membaca POSTGRES_PASSWORD."
}

db_exec() {
  # $1 = SQL
  local pass
  pass="$(db_pass)"
  docker exec -e PGPASSWORD="$pass" kasm_db \
    psql -h localhost -U kasmapp -d kasm -v ON_ERROR_STOP=1 -c "$1"
}

# ---------------------------------------------------------------- obs images
build_obs_images() {
  [ "$INSTALL_OBS" = "true" ] || { log "INSTALL_OBS=false, lewati build OBS."; return 0; }
  log "Build image custom/ubuntu-noble-obs:${KASM_IMAGE_TAG} ..."
  docker build --build-arg "KASM_TAG=${KASM_IMAGE_TAG}" \
    -t "custom/ubuntu-noble-obs:${KASM_IMAGE_TAG}" \
    "$SCRIPT_DIR/docker/obs-base" || fail "Build obs-base gagal."
  log "Build image custom/obs-studio:${KASM_IMAGE_TAG} ..."
  docker build --build-arg "OBS_BASE_IMAGE=custom/ubuntu-noble-obs:${KASM_IMAGE_TAG}" \
    -t "custom/obs-studio:${KASM_IMAGE_TAG}" \
    "$SCRIPT_DIR/docker/obs-app" || fail "Build obs-app gagal."
  log "Image OBS selesai."
}

# ---------------------------------------------------------------- register workspaces
register_workspace() {
  # $1 = image name, $2 = friendly name, $3 = description
  local img="$1" friendly="$2" desc="$3"
  log "Daftarkan workspace: $friendly"
  db_exec "
INSERT INTO images
SELECT uuid_generate_v4(), cores, '$desc',
  docker_registry, docker_token, docker_user, image_src,
  enabled, available, '$friendly',
  hash, memory, '$img',
  session_banner_id, session_banner_force_disabled,
  1280, 720,
  run_config, volume_mappings, persistent_profile_path,
  restrict_to_network, restrict_network_names,
  allow_network_selection, restrict_to_server, server_id,
  exec_config, restrict_to_zone, zone_id,
  filter_policy_id, filter_policy_force_disabled,
  session_time_limit, categories, require_gpu, gpu_count,
  hidden, notes, override_egress_gateways, image_type,
  server_pool_id, link_url, cpu_allocation_method,
  uncompressed_size_mb, launch_config, rdp_client_type,
  is_remote_app, remote_app_icon, remote_app_name,
  remote_app_program, remote_app_args
FROM images WHERE friendly_name='Ubuntu Noble'
AND NOT EXISTS (SELECT 1 FROM images WHERE name='$img');" > /dev/null
  db_exec "
INSERT INTO group_images (group_id, image_id)
SELECT g.group_id, i.image_id FROM groups g, images i
WHERE g.name='All Users' AND i.name='$img'
AND NOT EXISTS (
  SELECT 1 FROM group_images gi
  JOIN images ii ON gi.image_id = ii.image_id
  WHERE gi.group_id = g.group_id AND ii.name = '$img'
);" > /dev/null
  log "Workspace $friendly terdaftar."
}

# ---------------------------------------------------------------- passwords
reset_passwords() {
  [ -n "$KASM_ADMIN_PASSWORD" ] || fail "KASM_ADMIN_PASSWORD kosong."
  [ -n "$KASM_USER_PASSWORD" ] || fail "KASM_USER_PASSWORD kosong."
  log "Reset password admin & user..."
  KASM_ADMIN_PASSWORD="$KASM_ADMIN_PASSWORD" KASM_USER_PASSWORD="$KASM_USER_PASSWORD" \
  python3 - << 'PYEOF'
import hashlib, os, subprocess, uuid

def db(sql):
    pw = subprocess.check_output(
        ["sudo", "grep", "-oP", 'POSTGRES_PASSWORD: "\\K[^"]+',
         "/opt/kasm/current/docker/docker-compose.yaml"],
        text=True).strip()
    env = dict(os.environ, PGPASSWORD=pw)
    subprocess.run(
        ["docker", "exec", "-e", f"PGPASSWORD={pw}", "kasm_db",
         "psql", "-h", "localhost", "-U", "kasmapp", "-d", "kasm",
         "-v", "ON_ERROR_STOP=1", "-c", sql],
        check=True, env=env, capture_output=True, text=True)

def set_pw(username, password):
    salt = str(uuid.uuid4())
    h = hashlib.sha256((password + salt).encode()).hexdigest()
    # pakai dollar-quoting biar aman dari karakter khusus
    db(f"UPDATE users SET pw_hash='{h}', salt='{salt}', "
       f"failed_pw_attempts=0, locked=false WHERE username='{username}';")
    print(f"password {username} di-reset", flush=True)

set_pw("admin@kasm.local", os.environ["KASM_ADMIN_PASSWORD"])
set_pw("user@kasm.local", os.environ["KASM_USER_PASSWORD"])
PYEOF
  log "Password di-reset."
}

# ---------------------------------------------------------------- verify
verify_login() {
  log "Verifikasi login via API..."
  local token
  token=$(curl -sk --max-time 20 -X POST https://127.0.0.1/api/authenticate \
    -H 'Content-Type: application/json' \
    -d "{\"username\":\"user@kasm.local\",\"password\":\"$KASM_USER_PASSWORD\"}" \
    | python3 -c "import sys,json; print(json.load(sys.stdin).get('token',''))" 2>/dev/null)
  [ -n "$token" ] || fail "Login user@kasm.local via API gagal."
  log "Login API OK."
}

# ---------------------------------------------------------------- summary
print_summary() {
  local tsip="${TSIP:-<ip-tailscale>}"
  {
    echo ""
    echo "===================================================================="
    echo " KASM WORKSPACES READY"
    echo "===================================================================="
    echo " URL   : https://$tsip  (abaikan peringatan sertifikat self-signed)"
    echo " Admin : admin@kasm.local"
    echo " User  : user@kasm.local"
    echo ""
    echo " Workspace tambahan (jika INSTALL_OBS=true):"
    echo "   - OBS Studio (standalone, auto-start)"
    echo "   - Ubuntu Noble + OBS (desktop lengkap)"
    echo "===================================================================="
  } | tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}"
}

main() {
  command -v docker > /dev/null || fail "docker tidak ditemukan."
  download_kasm
  install_kasm
  sleep 10
  build_obs_images
  if [ "$INSTALL_OBS" = "true" ]; then
    register_workspace "custom/obs-studio:${KASM_IMAGE_TAG}" \
      "OBS Studio" "OBS Studio untuk live streaming, terbuka otomatis."
    register_workspace "custom/ubuntu-noble-obs:${KASM_IMAGE_TAG}" \
      "Ubuntu Noble + OBS" "Ubuntu 24.04 desktop dengan OBS Studio preinstalled."
  fi
  reset_passwords
  verify_login
  print_summary
  log "Selesai."
}

main "$@"
