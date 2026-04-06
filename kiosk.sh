#!/bin/bash
export DISPLAY=:0
export XDG_RUNTIME_DIR=/run/user/1000
unclutter -idle 0 &
 
PICS_DIR="/home/cds1438/active_pics"
NEW_PICS="/home/cds1438/new_pics"
V1="/home/cds1438/v1.mp4"
L1="/home/cds1438/l1.txt"
LOG="/home/cds1438/kiosk.log"
GH="https://raw.githubusercontent.com/fdwsc2005/front-tv-board/main"
YTDLP="/home/cds1438/.local/bin/yt-dlp"
VIDEO_TIMEOUT=7200
 
mkdir -p "$PICS_DIR" "$NEW_PICS"
 
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
    pkill -x mpv 2>/dev/null
    log "Night window — screen off."
 
    # Update slides
    log "Checking for slide updates..."
    ALL_OK=true
    for i in {1..9}; do
      wget -q --timeout=30 --tries=3 -O "$NEW_PICS/$i.png" "$GH/$i.png" || {
        log "Failed to download slide $i."
        ALL_OK=false
      }
    done
    if $ALL_OK; then
      mv "$NEW_PICS"/*.png "$PICS_DIR"/
      log "Slides updated."
    else
      log "Slide update incomplete — keeping existing slides."
      rm -f "$NEW_PICS"/*.png
    fi
 
    # Update video 1
    URL1=$(curl -sf --max-time 15 "$GH/video_url.txt" | tr -d '[:space:]')
    SAVED1=$(cat "$L1" 2>/dev/null | tr -d '[:space:]')
    if [ -n "$URL1" ] && [ "$URL1" != "$SAVED1" ]; then
      log "New URL for video 1 — downloading..."
      TMP="${V1}.tmp"
      "$YTDLP" --format "best[ext=mp4]" --no-playlist -o "$TMP" "$URL1" && \
        mv "$TMP" "$V1" && echo "$URL1" > "$L1" && log "Video 1 downloaded." || \
        log "Video 1 download failed — keeping existing."
      rm -f "$TMP"
    else
      log "Video 1 unchanged."
    fi
 
    sleep 600
    continue
  fi
 
  # Day mode
  vcgencmd display_power 1
  log "Day window — screen on. Starting playback cycle."
 
  # Play slides
  if ls "$PICS_DIR"/*.png &>/dev/null; then
    log "Playing slides..."
    timeout --kill-after=10 360 \
      mpv \
        --fullscreen \
        --vo=gpu \
        --gpu-context=x11egl \
        --profile=fast \
        --image-display-duration=30 \
        --no-osc \
        --no-osd-bar \
        --no-sub \
        --really-quiet \
        --no-terminal \
        "$PICS_DIR"/*.png
  else
    log "No slides found — skipping."
  fi
 
  # Play video 1
  pkill -x mpv 2>/dev/null
  sleep 3
  if [ -f "$V1" ]; then
    log "Playing video 1..."
    timeout --kill-after=10 "$VIDEO_TIMEOUT" \
      mpv \
        --fullscreen \
        --vo=gpu \
        --gpu-context=x11egl \
        --hwdec=v4l2m2m \
        --profile=fast \
        --no-osc \
        --no-osd-bar \
        --really-quiet \
        --no-sub \
        --sub-auto=no \
        --sid=no \
        --no-terminal \
        --audio-device=alsa/plughw:CARD=vc4hdmi,DEV=0 \
        --keep-open=no \
        "$V1"
    log "Video 1 finished."
  else
    log "Video 1 not found — skipping."
  fi
 
done
