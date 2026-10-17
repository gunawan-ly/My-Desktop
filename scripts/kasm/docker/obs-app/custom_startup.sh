#!/usr/bin/env bash
# Auto-start OBS Studio saat sesi Kasm dimulai.
# Kasm otomatis menjalankan /dockerstartup/custom_startup.sh kalau file ini ada.
set -e
START_COMMAND="obs"
PGREP="obs"
ARGS=${APP_ARGS:-""}
kasm_startup() {
    if [ -z "$DISABLE_CUSTOM_STARTUP" ]; then
        echo "Starting OBS Studio"
        while true; do
            if ! pgrep -x "$PGREP" > /dev/null 2>&1; then
                /usr/bin/filter_ready
                /usr/bin/desktop_ready
                $START_COMMAND $ARGS &
            fi
            sleep 5
        done
    fi
}
kasm_startup
