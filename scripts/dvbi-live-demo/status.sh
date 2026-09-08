#!/bin/bash
# What is running, and whether each channel is actually still live.
#
# A process being up does not mean a channel is: an encoder can exit or stall while its last
# manifest stays on disk and keeps returning 200. The publishTime check below is what
# distinguishes a live presentation from a stale one, so it is the line to read first.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source env.sh
source lib.sh

echo "processes:"
found=0
for pidfile in "$PID_DIR"/*.pid; do
    [[ -e "$pidfile" ]] || continue
    found=1
    name=$(basename "$pidfile" .pid)
    pid=$(cat "$pidfile")
    if kill -0 "$pid" 2>/dev/null; then
        printf '  \033[1;32mUP  \033[0m %-30s pid %s\n' "$name" "$pid"
    else
        printf '  \033[1;31mDOWN\033[0m %-30s (stale pidfile, see %s)\n' "$name" "$LOG_DIR/$name.log"
    fi
done
[[ $found -eq 1 ]] || echo "  nothing started by these scripts is recorded as running"

echo
echo "endpoints:"
# Any HTTP response means the server is listening. The origin's own root returns 404 by design
# (static files, directory listing off), so the status code alone is not the health signal here.
for entry in "media origin|$MEDIA_ORIGIN/" "admin|$ADMIN_ORIGIN/service-list.xml" "client|$CLIENT_ORIGIN/health"; do
    IFS='|' read -r label url <<< "$entry"
    code=$(curl -s -o /dev/null -w '%{http_code}' -m 3 "$url" 2>/dev/null || echo 000)
    if [[ "$code" == "000" ]]; then
        printf '  \033[1;31m%-14s no response\033[0m  %s\n' "$label" "$url"
    else
        printf '  \033[1;32m%-14s listening\033[0m  (HTTP %s)  %s\n' "$label" "$code" "$url"
    fi
done

echo
echo "channels:"
now=$(date -u +%s)
while IFS='|' read -r id name lcn source stream; do
    mpd=$(curl -s -m 5 "$MEDIA_ORIGIN/$stream/manifest.mpd" 2>/dev/null || true)
    if [[ "$mpd" != *"<MPD"* ]]; then
        printf '  \033[1;31m%-12s no manifest at %s\033[0m\n' "$stream" "$MEDIA_ORIGIN/$stream/manifest.mpd"
        continue
    fi
    published=$(grep -oP 'publishTime="\K[^"]+' <<< "$mpd" | head -1)
    segs=$(ls "$MEDIA_DIR/public/$stream"/chunk-stream0-*.m4s 2>/dev/null | wc -l)
    age=$(( now - $(date -u -d "$published" +%s 2>/dev/null || echo "$now") ))
    # The manifest is rewritten once per segment, so an age well past one segment duration means
    # the encoder is no longer publishing even though the file is still being served.
    if (( age > LIVE_SEG_DURATION * 4 )); then
        printf '  \033[1;33m%-12s STALE  last published %ss ago, %s segments\033[0m\n' "$stream" "$age" "$segs"
    else
        printf '  \033[1;32m%-12s LIVE\033[0m   last published %ss ago, %s segments\n' "$stream" "$age" "$segs"
    fi
done < <(channel_lines)
