#!/usr/bin/env bash
# Build image ArtCraft Suite + 14 workspace single-app, daftarkan ke Kasm.
# Dipakai oleh workflow .github/workflows/kasm-workspace.yml
# (langkah opsional, dikontrol input install_artcraft).
#
# Urutan:
#   1. Download .deb launcher + 13 aplikasi (versi di-pin di bawah)
#   2. Build image custom/artcraft-suite (desktop lengkap)
#   3. Build 14 image single-app (numpang layer suite, hanya tambah startup script)
#   4. Daftarkan 15 workspace ke database Kasm + assign ke All Users
#   5. Pasang icon asli tiap aplikasi sebagai thumbnail dashboard
#
# Env:
#   KASM_IMAGE_TAG  - tag image (default 1.17.0)
set -uo pipefail

log() { printf '[artcraft] %s\n' "$*"; }
fail() { log "FATAL: $*"; exit 1; }

KASM_IMAGE_TAG="${KASM_IMAGE_TAG:-1.17.0}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="/tmp/artcraft-build"
SUITE_DIR="$SCRIPT_DIR/docker/artcraft-suite"

# Versi di-pin (teruji 17 Okt 2026)
LAUNCHER_VER="0.4.1"
declare -A APP_VERS=(
  [photocraft]="0.9.0"
  [pdfcraft]="0.8.0"
  [figcraft]="0.6.0"
  [vectorcraft]="0.12.0"
  [filmcraft]="0.8.0"
  [lightcraft]="0.8.0"
  [effectcraft]="0.10.0"
  [designcraft]="0.8.0"
  [wordcraft]="0.7.0"
  [gridcraft]="0.7.0"
  [deckcraft]="0.7.0"
  [cadcraft]="0.7.0"
  [soundcraft]="0.7.0"
)

# Nama tampilan tiap aplikasi
declare -A APP_NAMES=(
  [artcraft-launcher]="ArtCraft Launcher"
  [photocraft]="PhotoCraft"
  [pdfcraft]="PdfCraft"
  [figcraft]="FigCraft"
  [vectorcraft]="VectorCraft"
  [filmcraft]="FilmCraft"
  [lightcraft]="LightCraft"
  [effectcraft]="EffectCraft"
  [designcraft]="DesignCraft"
  [wordcraft]="WordCraft"
  [gridcraft]="GridCraft"
  [deckcraft]="DeckCraft"
  [cadcraft]="CADCraft"
  [soundcraft]="SoundCraft"
)

# Deskripsi singkat tiap aplikasi
declare -A APP_DESCS=(
  [artcraft-launcher]="Kelola dan update semua aplikasi Craft Suite"
  [photocraft]="Edit foto: layers, masks, file PSD (alternatif Photoshop)"
  [pdfcraft]="Baca, atur, tanda tangani PDF (alternatif Acrobat)"
  [figcraft]="Desain interface dan prototyping (alternatif Figma)"
  [vectorcraft]="Ilustrasi vektor (alternatif Illustrator)"
  [filmcraft]="Edit video, warna, suara (alternatif Premiere Pro)"
  [lightcraft]="Kelola foto dan RAW developer (alternatif Lightroom)"
  [effectcraft]="Motion graphics dan efek visual (alternatif After Effects)"
  [designcraft]="Layout halaman dan publishing (alternatif InDesign)"
  [wordcraft]="Pengolah kata, dukung .docx (alternatif Word)"
  [gridcraft]="Spreadsheet dan analisis data (alternatif Excel)"
  [deckcraft]="Presentasi dan slideshow (alternatif PowerPoint)"
  [cadcraft]="CAD dan drafting (alternatif AutoCAD)"
  [soundcraft]="Rekam, edit, mixing audio (alternatif Pro Tools)"
)

download_debs() {
  log "Download .deb ArtCraft..."
  mkdir -p "$WORK_DIR/debs"
  local base="https://github.com/storytold"

  curl -fSL --max-time 120 -o "$WORK_DIR/debs/artcraft-launcher.deb" \
    "$base/craft-launcher/releases/download/v${LAUNCHER_VER}/artcraft-launcher-${LAUNCHER_VER}-linux-x86_64.deb" \
    || fail "Download launcher gagal."

  for app in "${!APP_VERS[@]}"; do
    local ver="${APP_VERS[$app]}"
    curl -fSL --max-time 180 -o "$WORK_DIR/debs/${app}.deb" \
      "$base/${app}/releases/download/v${ver}/${app}-${ver}-linux-x86_64.deb" \
      || fail "Download $app gagal."
    log "  $app v$ver OK"
  done
  log "Total: $(du -sh "$WORK_DIR/debs" | cut -f1)"
}

download_icons() {
  log "Download icon aplikasi..."
  mkdir -p "$WORK_DIR/icons"
  for app in "${!APP_VERS[@]}"; do
    curl -fSL --max-time 30 -o "$WORK_DIR/icons/${app}.png" \
      "https://raw.githubusercontent.com/storytold/${app}/main/assets/app-icon/hicolor/128x128/apps/ai.storyteller.${app}.png" \
      2>/dev/null || log "  icon $app gagal, pakai default"
  done
  curl -fSL --max-time 30 -o "$WORK_DIR/icons/artcraft-launcher.png" \
    "https://raw.githubusercontent.com/storytold/craft-launcher/main/assets/app-icon/hicolor/128x128/apps/ai.storyteller.artcraft-launcher.png" \
    2>/dev/null || log "  icon launcher gagal, pakai default"
}

build_suite() {
  log "Build image custom/artcraft-suite:${KASM_IMAGE_TAG} ..."
  mkdir -p "$SUITE_DIR/debs"
  cp "$WORK_DIR/debs/"*.deb "$SUITE_DIR/debs/"
  docker build --build-arg "KASM_TAG=${KASM_IMAGE_TAG}" \
    -t "custom/artcraft-suite:${KASM_IMAGE_TAG}" \
    "$SUITE_DIR" || fail "Build suite gagal."
  rm -rf "$SUITE_DIR/debs"
  log "Suite selesai."
}

build_single_apps() {
  log "Build 14 image single-app..."
  local app_dir="$WORK_DIR/app-build"
  for bin in "${!APP_NAMES[@]}"; do
    local name="${APP_NAMES[$bin]}"
    rm -rf "$app_dir" && mkdir -p "$app_dir"
    cp "$SUITE_DIR/xfce4-desktop-single-app.xml" "$app_dir/xfce4-desktop.xml"

    cat > "$app_dir/custom_startup.sh" << EOF
#!/usr/bin/env bash
# Auto-start $name maximized saat sesi Kasm dimulai.
set -e
START_COMMAND="$bin"
PGREP="$bin"
MAXIMIZE="true"
MAXIMIZE_NAME="$name"
ARGS=\${APP_ARGS:-""}
kasm_startup() {
    if [ -z "\$DISABLE_CUSTOM_STARTUP" ]; then
        echo "Starting $name"
        MAXIMIZE="\$MAXIMIZE" MAXIMIZE_NAME="\$MAXIMIZE_NAME" /dockerstartup/maximize_window.sh &
        while true; do
            if ! pgrep -x "\$PGREP" > /dev/null 2>&1; then
                /usr/bin/filter_ready
                /usr/bin/desktop_ready
                \$START_COMMAND \$ARGS &
            fi
            sleep 5
        done
    fi
}
kasm_startup
EOF
    chmod +x "$app_dir/custom_startup.sh"

    cat > "$app_dir/Dockerfile" << EOF
FROM custom/artcraft-suite:${KASM_IMAGE_TAG}
USER root
# Single-app mode ala kasmweb/chrome: copot panel + matikan desktop icons
RUN apt-get remove -y xfce4-panel 2>/dev/null || true && apt-get autoremove -y 2>/dev/null || true
COPY xfce4-desktop.xml /home/kasm-default-profile/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml
COPY custom_startup.sh /dockerstartup/custom_startup.sh
RUN chmod +x /dockerstartup/custom_startup.sh && chown 1000:0 /home/kasm-default-profile/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml
USER 1000
EOF
    docker build -q -t "custom/artcraft-${bin}:${KASM_IMAGE_TAG}" "$app_dir" \
      || fail "Build $bin gagal."
    log "  $name OK"
  done
}

register_workspaces() {
  log "Daftarkan workspace ke Kasm..."
  local sql="$WORK_DIR/register.sql"

  {
    echo "-- Suite (desktop lengkap)"
    echo "INSERT INTO images (cores, description, docker_registry, docker_token, docker_user,"
    echo "  image_src, enabled, available, friendly_name, hash, memory, name,"
    echo "  session_banner_id, session_banner_force_disabled, x_res, y_res,"
    echo "  run_config, volume_mappings, persistent_profile_path, restrict_to_network,"
    echo "  restrict_network_names, allow_network_selection, restrict_to_server,"
    echo "  server_id, exec_config, restrict_to_zone, zone_id, filter_policy_id,"
    echo "  filter_policy_force_disabled, session_time_limit, categories, require_gpu,"
    echo "  gpu_count, hidden, notes, override_egress_gateways, image_type,"
    echo "  server_pool_id, link_url, cpu_allocation_method, uncompressed_size_mb,"
    echo "  launch_config, rdp_client_type, is_remote_app, remote_app_icon,"
    echo "  remote_app_name, remote_app_program, remote_app_args)"
    echo "SELECT cores, 'ArtCraft Suite: launcher + 13 aplikasi Craft Suite (alternatif Adobe/Office open-source)',"
    echo "  docker_registry, docker_token, docker_user,"
    echo "  image_src, enabled, available, 'ArtCraft Suite',"
    echo "  hash, memory, 'custom/artcraft-suite:${KASM_IMAGE_TAG}',"
    echo "  session_banner_id, session_banner_force_disabled, x_res, y_res,"
    echo "  run_config, volume_mappings, persistent_profile_path, restrict_to_network,"
    echo "  restrict_network_names, allow_network_selection, restrict_to_server,"
    echo "  server_id, exec_config, restrict_to_zone, zone_id, filter_policy_id,"
    echo "  filter_policy_force_disabled, session_time_limit, categories, require_gpu,"
    echo "  gpu_count, hidden, notes, override_egress_gateways, image_type,"
    echo "  server_pool_id, link_url, cpu_allocation_method, uncompressed_size_mb,"
    echo "  launch_config, rdp_client_type, is_remote_app, remote_app_icon,"
    echo "  remote_app_name, remote_app_program, remote_app_args"
    echo "FROM images WHERE name = 'kasmweb/ubuntu-noble-desktop:${KASM_IMAGE_TAG}' LIMIT 1"
    echo "ON CONFLICT DO NOTHING;"
    echo ""
    echo "-- 14 single-app"
    for bin in "${!APP_NAMES[@]}"; do
      local name="${APP_NAMES[$bin]}"
      local desc="${APP_DESCS[$bin]}"
      echo "INSERT INTO images (cores, description, docker_registry, docker_token, docker_user,"
      echo "  image_src, enabled, available, friendly_name, hash, memory, name,"
      echo "  session_banner_id, session_banner_force_disabled, x_res, y_res,"
      echo "  run_config, volume_mappings, persistent_profile_path, restrict_to_network,"
      echo "  restrict_network_names, allow_network_selection, restrict_to_server,"
      echo "  server_id, exec_config, restrict_to_zone, zone_id, filter_policy_id,"
      echo "  filter_policy_force_disabled, session_time_limit, categories, require_gpu,"
      echo "  gpu_count, hidden, notes, override_egress_gateways, image_type,"
      echo "  server_pool_id, link_url, cpu_allocation_method, uncompressed_size_mb,"
      echo "  launch_config, rdp_client_type, is_remote_app, remote_app_icon,"
      echo "  remote_app_name, remote_app_program, remote_app_args)"
      echo "SELECT cores, '${desc}',"
      echo "  docker_registry, docker_token, docker_user,"
      echo "  image_src, enabled, available, '${name}',"
      echo "  hash, memory, 'custom/artcraft-${bin}:${KASM_IMAGE_TAG}',"
      echo "  session_banner_id, session_banner_force_disabled, x_res, y_res,"
      echo "  run_config, volume_mappings, persistent_profile_path, restrict_to_network,"
      echo "  restrict_network_names, allow_network_selection, restrict_to_server,"
      echo "  server_id, exec_config, restrict_to_zone, zone_id, filter_policy_id,"
      echo "  filter_policy_force_disabled, session_time_limit, categories, require_gpu,"
      echo "  gpu_count, hidden, notes, override_egress_gateways, image_type,"
      echo "  server_pool_id, link_url, cpu_allocation_method, uncompressed_size_mb,"
      echo "  launch_config, rdp_client_type, is_remote_app, remote_app_icon,"
      echo "  remote_app_name, remote_app_program, remote_app_args"
      echo "FROM images WHERE name = 'kasmweb/ubuntu-noble-desktop:${KASM_IMAGE_TAG}' LIMIT 1"
      echo "ON CONFLICT DO NOTHING;"
      echo ""
    done
    echo "-- Assign semua ke All Users"
    echo "INSERT INTO group_images (group_id, image_id)"
    echo "SELECT g.group_id, i.image_id FROM groups g, images i"
    echo "WHERE g.name = 'All Users' AND i.name LIKE 'custom/artcraft%:${KASM_IMAGE_TAG}'"
    echo "ON CONFLICT DO NOTHING;"
  } > "$sql"

  docker exec -i kasm_db psql -U kasmapp -d kasm < "$sql" \
    || fail "Registrasi workspace gagal."
  log "15 workspace terdaftar."
}

install_thumbnails() {
  log "Pasang thumbnail icon..."
  for bin in "${!APP_NAMES[@]}"; do
    local icon="$WORK_DIR/icons/${bin}.png"
    [ -f "$icon" ] || continue
    docker cp "$icon" "kasm_proxy:/srv/www/img/thumbnails/artcraft-${bin}.png" 2>/dev/null || true
    docker exec kasm_db psql -U kasmapp -d kasm -t -c \
      "UPDATE images SET image_src = 'img/thumbnails/artcraft-${bin}.png' WHERE name = 'custom/artcraft-${bin}:${KASM_IMAGE_TAG}';" \
      > /dev/null 2>&1 || true
  done
  # Suite pakai icon PhotoCraft
  docker exec kasm_db psql -U kasmapp -d kasm -t -c \
    "UPDATE images SET image_src = 'img/thumbnails/artcraft-photocraft.png' WHERE name = 'custom/artcraft-suite:${KASM_IMAGE_TAG}';" \
    > /dev/null 2>&1 || true
  log "Thumbnail selesai."
}

main() {
  command -v docker > /dev/null || fail "docker tidak ditemukan."
  download_debs
  download_icons
  build_suite
  build_single_apps
  register_workspaces
  install_thumbnails
  log "ArtCraft selesai: 15 workspace (1 suite + 14 single-app)."
}

main "$@"
