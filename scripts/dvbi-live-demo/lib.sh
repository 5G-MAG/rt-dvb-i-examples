#!/bin/bash
# License: 5G-MAG Public License (v1.0)
# Authors: Jordi J. Gimenez (5G-MAG)
# Copyright: (C) 2026 5G-MAG Association
#
# For full license terms please see the LICENSE file distributed with this
# program. If this file is missing then the license can be retrieved from
# https://www.5g-mag.com/license

# Helpers shared by the DVB-I live demo scripts. Source after env.sh.

log()  { printf '\033[1;34m[%s]\033[0m %s\n' "$(date +%H:%M:%S)" "$*"; }
warn() { printf '\033[1;33m[%s] %s\033[0m\n' "$(date +%H:%M:%S)" "$*"; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

ensure_dirs() { mkdir -p "$LOG_DIR" "$PID_DIR"; }

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "$1 not found. $2"
}

# Reads channels.json and prints one "id|name|lcn|source|stream" line per channel, so the
# shell scripts and write-service-list.py work from the same definition rather than each
# carrying their own copy of the line-up.
# DEMO_CHANNELS limits the line-up to the ids it names (space or comma separated), for a machine
# that cannot encode all of them at once: one looping encoder per channel is this demo's largest
# cost by far. The service list is generated from the same filtered set, so the receiver is never
# offered a channel that nothing is encoding. Unset, the whole line-up runs.
channel_lines() {
    python3 - "$CHANNELS_FILE" <<'PYEOF'
import json, os, sys
only = [x for x in os.environ.get("DEMO_CHANNELS", "").replace(",", " ").split() if x]
for c in json.load(open(sys.argv[1]))["channels"]:
    if only and c["id"] not in only: continue
    print("|".join(str(c[k]) for k in ("id", "name", "lcn", "source", "stream")))
PYEOF
}

is_running() {  # is_running <name>
    local pidfile="$PID_DIR/$1.pid"
    [[ -f "$pidfile" ]] && kill -0 "$(cat "$pidfile")" 2>/dev/null
}

run_bg() {  # run_bg <name> <command...>
    local name="$1"; shift
    if is_running "$name"; then
        log "$name already running (pid $(cat "$PID_DIR/$name.pid"))"
        return 0
    fi
    nohup "$@" > "$LOG_DIR/$name.log" 2>&1 &
    echo $! > "$PID_DIR/$name.pid"
    disown
    log "$name started (pid $(cat "$PID_DIR/$name.pid")), log: $LOG_DIR/$name.log"
}

wait_http() {  # wait_http <url> <seconds>
    local i
    for ((i = 0; i < $2; i++)); do
        curl -sf -m 3 -o /dev/null "$1" && return 0
        sleep 1
    done
    return 1
}

# A live DASH presentation is servable once its manifest both parses as an MPD and names at
# least one segment. Waiting for the manifest alone is not enough: ffmpeg writes the MPD before
# the first segment exists, and a receiver that fetches it in that window sees an empty
# presentation and gives up rather than retrying.
wait_presentation() {  # wait_presentation <stream> <seconds>
    local body i
    for ((i = 0; i < $2; i++)); do
        body=$(curl -s -m 5 "$MEDIA_ORIGIN/$1/manifest.mpd" 2>/dev/null || true)
        [[ "$body" == *"<MPD"* && "$body" == *"<S "* ]] && return 0
        sleep 1
    done
    return 1
}

# The channel ids in channels.json that carry a logo, unfiltered by DEMO_CHANNELS: install_logos
# copies every one of them into the provider.
logo_ids() {
    python3 - "$CHANNELS_FILE" <<'PYEOF'
import json, sys
for c in json.load(open(sys.argv[1]))["channels"]:
    if c.get("logo"): print(c["id"])
PYEOF
}

# Saves the provider files this demo overwrites (config.json and the channel logos) into
# PROVIDER_SAVED_DIR, once: a copy already there is the state from before the first start and is
# kept, so a second start or a regen-service-list.sh run does not save the demo's own list over it.
# A file that did not exist is recorded as absent, so that restoring removes it. Written to a
# temporary directory and renamed into place, so an interrupted save never looks complete.
save_provider_state() {
    [[ -d "$PROVIDER_SAVED_DIR" ]] && return 0
    local tmp="$PROVIDER_SAVED_DIR.tmp" id
    rm -rf "$tmp"; mkdir -p "$tmp/logos"
    if [[ -f "$ADMIN_DIR/config.json" ]]; then cp -p "$ADMIN_DIR/config.json" "$tmp/config.json"
    else touch "$tmp/config.json.absent"; fi
    while read -r id; do
        if [[ -f "$ADMIN_DIR/public/logos/uploaded/$id.png" ]]; then
            cp -p "$ADMIN_DIR/public/logos/uploaded/$id.png" "$tmp/logos/$id.png"
        else
            touch "$tmp/logos/$id.png.absent"
        fi
    done < <(logo_ids)
    mv "$tmp" "$PROVIDER_SAVED_DIR"
    log "saved the provider's config.json and channel logos to $PROVIDER_SAVED_DIR"
}

# Puts back what save_provider_state saved, contents and modification times, and forgets the copy.
restore_provider_state() {
    [[ -d "$PROVIDER_SAVED_DIR" ]] || return 0
    local f name
    if [[ -f "$PROVIDER_SAVED_DIR/config.json" ]]; then cp -p "$PROVIDER_SAVED_DIR/config.json" "$ADMIN_DIR/config.json"
    elif [[ -f "$PROVIDER_SAVED_DIR/config.json.absent" ]]; then rm -f "$ADMIN_DIR/config.json"; fi
    for f in "$PROVIDER_SAVED_DIR"/logos/*; do
        [[ -e "$f" ]] || continue
        name=$(basename "$f")
        if [[ "$name" == *.absent ]]; then rm -f "$ADMIN_DIR/public/logos/uploaded/${name%.absent}"
        else cp -p "$f" "$ADMIN_DIR/public/logos/uploaded/$name"; fi
    done
    rm -rf "$PROVIDER_SAVED_DIR"
    log "restored the provider's config.json and channel logos from before the demo"
}

port_pid() {  # port_pid <port>, prints the pid listening on it, if any
    ss -ltnpH "sport = :$1" 2>/dev/null | grep -oP 'pid=\K[0-9]+' | head -1
}
