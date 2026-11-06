#!/usr/bin/env bash
# chat_apps_verify.sh — Potret layar verifikasi device aplikasi chat.
#
# Dipakai workflow Sesi Runner (V2) sesudah langkah install aplikasi chat.
# Untuk tiap aplikasi (Telegram, WhatsApp, Discord):
#   1. Buka aplikasinya (open -a).
#   2. Tunggu sampai layar verifikasi device-nya tampil
#      (WhatsApp: tautkan perangkat via QR / nomor telepon;
#       Telegram: login via QR / nomor; Discord: form login).
#   3. Aktifkan ke depan lalu potret seluruh layar dengan screencapture.
#
# Hasil: /tmp/verifikasi-<app>.png, di-upload workflow sebagai artifact
# dan dirujuk dari issue verifikasi yang dibuat untuk run itu.
#
# Skrip ini TIDAK boleh menggagalkan sesi utama: semua kegagalan dicatat
# sebagai warning dan aplikasi berikutnya tetap diproses. Tanpa set -e.

set -uo pipefail

APPS=("Telegram" "WhatsApp" "Discord")
# Waktu tunggu per aplikasi sampai layar verifikasinya tampil penuh.
WAIT_SECONDS="${CHAT_VERIFY_WAIT_SECONDS:-25}"

slug() {
  echo "$1" | tr '[:upper:]' '[:lower:]'
}

for app in "${APPS[@]}"; do
  out="/tmp/verifikasi-$(slug "$app").png"
  echo "=== $app ==="
  if ! open -a "$app" 2>/dev/null; then
    echo "::warning::$app tidak ditemukan atau gagal dibuka; lewati."
    continue
  fi
  echo "Menunggu ${WAIT_SECONDS} dtk sampai layar verifikasi $app tampil..."
  sleep "$WAIT_SECONDS"
  # Bawa jendela aplikasi ke depan agar yang terpotret adalah layarnya.
  osascript -e "tell application \"$app\" to activate" >/dev/null 2>&1 || true
  sleep 3
  if screencapture -x "$out" 2>/dev/null; then
    echo "Screenshot $app tersimpan: $out"
  else
    echo "::warning::screencapture untuk $app gagal."
  fi
done

echo "=== Ringkasan screenshot verifikasi ==="
ls -la /tmp/verifikasi-*.png 2>/dev/null \
  || echo "Tidak ada screenshot verifikasi yang berhasil dibuat."
exit 0
