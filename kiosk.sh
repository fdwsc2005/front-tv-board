#!/bin/bash
export DISPLAY=:0
export XDG_RUNTIME_DIR=/run/user/1000
unclutter -idle 0 &

PICS_DIR="/home/cds1438/active_pics"
NEW_PICS="/home/cds1438/new_pics"
V1="/home/cds1438/v1.mp4"
V2="/home/cds1438/v2.mp4"
L1="/home/cds1438/l1.txt"
L2="/home/cds1438/l2.txt"
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

play_video() {
  local FILE="$1"
  [ -f "$FILE" ] || { log "Skipping $FILE — not found."; return; }
  log "Playing: $FILE"
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
      "$FILE"
  local EXIT=$?
  if [ "$EXIT" -eq 124 ]; then
    log "WARNING: mpv timed out on $FILE — force killed."
  elif [ "$EXIT" -ne 0 ]; then
    log "WARNING: mpv exited with code $EXIT on $FILE."
  fi
  sleep 2
}

download_video() {
  local URL="$1"
  local DEST="$2"
  local TMP="${DEST}.tmp"
  local ATTEMPT=0
  local SUCCESS=false
  while [ "$ATTEMPT" -lt 3 ]; do
    ATTEMPT=$((ATTEMPT + 1))
    log "Downloading $(basename $DEST) — attempt $ATTEMPT of 3..."
    "$YTDLP" \
      --format "best[ext=mp4]" \
      --no-playlist \
      --no-embed-metadata \
      --retries 3 \
      --fragment-retries 3 \
      --socket-timeout 30 \
      -o "$TMP" \
      "$URL" && SUCCESS=true && break
    log "Attempt $ATTEMPT failed. Waiting 15s..."
    sleep 15
  done
  if $SUCCESS; then
    mv "$TMP" "$DEST"
    log "Download complete: $(basename $DEST)"
  else
    rm -f "$TMP"
    log "All attempts failed — keeping existing file."
  fi
}

while true; do
  HOUR=$(date +%-H)

  if [ "$HOUR" -ge 19 ] || [ "$HOUR" -lt 9 ]; then
    vcgencmd display_power 0
    pkill -x mpv 2>/dev/null
    log "Night window — screen off."
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
    URL1=$(curl -sf --max-time 15 "$GH/video_url.txt" | tr -d '[:space:]')
    SAVED1=$(cat "$L1" 2>/dev/null | tr -d '[:space:]')
    if [ -n "$URL1" ] && [ "$URL1" != "$SAVED1" ]; then
      log "New URL for video 1."
      download_video "$URL1" "$V1" && echo "$URL1" > "$L1"
    else
      log "Video 1 unchanged."
    fi
    URL2=$(curl -sf --max-time 15 "$GH/video_url_2.txt" | tr -d '[:space:]')
    SAVED2=$(cat "$L2" 2>/dev/null | tr -d '[:space:]')
    if [ -n "$URL2" ] && [ "$URL2" != "$SAVED2" ]; then
      log "New URL for video 2."
      download_video "$URL2" "$V2" && echo "$URL2" > "$L2"
    else
      log "Video 2 unchanged."
    fi
    sleep 600
    continue
  fi

  vcgencmd display_power 1
  log "Day window — screen on. Starting playback cycle."
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
  pkill -x mpv 2>/dev/null; sleep 1
  play_video "$V1"
  pkill -x mpv 2>/dev/null; sleep 1
  play_video "$V2"
done
