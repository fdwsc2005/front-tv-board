#!/bin/bash
export DISPLAY=:0
export XDG_RUNTIME_DIR=/run/user/1000
unclutter -idle 0 &

LOG="/home/cds1438/kiosk.log"
URL="https://fdwsc2005.github.io/front-tv-board/"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"
  tail -n 500 "$LOG" > "${LOG}.tmp" && mv "${LOG}.tmp" "$LOG"
}

log "Script started. Waiting for network..."
WAIT=0
until curl -sf --max-time 5 "https://github.com" > /dev/null 2>&1; do
  sleep 5
  WAIT=$((WAIT + 5))
  if [ "$WAIT" -ge 120 ]; then
    log "Network not available after 120s — continuing offline."
    break
  fi
done
log "Network ready (waited ${WAIT}s)."

while true; do
  HOUR=$(date +%-H)

  if [ "$HOUR" -ge 19 ] || [ "$HOUR" -lt 9 ]; then
    vcgencmd display_power 0
    pkill -f chromium 2>/dev/null
    log "Night window — screen off."
    sleep 600
    continue
  fi

  vcgencmd display_power 1
  log "Day window — screen on. Launching Chromium..."

  chromium \
    --kiosk \
    --noerrdialogs \
    --disable-infobars \
    --disable-session-crashed-bubble \
    --disable-restore-session-state \
    --autoplay-policy=no-user-gesture-required \
    --disable-features=TranslateUI \
    --check-for-update-interval=31536000 \
    "$URL" 2>/dev/null

  log "Chromium exited — restarting in 5s..."
  sleep 5
done
