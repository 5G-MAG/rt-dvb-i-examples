#!/bin/bash
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

# Whether a server is listening, regardless of what it answers. The media origin serves static
# files with directory listing off, so its own root legitimately returns 404: a check that
# required 2xx there would report a healthy origin as down. Any HTTP response at all proves the
# server is up, which is what this check is for.
wait_http_any() {  # wait_http_any <url> <seconds>
    local i code
    for ((i = 0; i < $2; i++)); do
        # curl prints 000 AND exits non-zero when it cannot connect, so a "|| echo 000" fallback
        # appends a second one and yields "000000", which compares unequal to "000" and made this
        # check report a dead server as up. Take curl's output as it is and treat empty as 000.
        code=$(curl -s -o /dev/null -w '%{http_code}' -m 3 "$1" 2>/dev/null)
        [[ -z "$code" ]] && code=000
        [[ "$code" != "000" ]] && return 0
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

port_pid() {  # port_pid <port>, prints the pid listening on it, if any
    ss -ltnpH "sport = :$1" 2>/dev/null | grep -oP 'pid=\K[0-9]+' | head -1
}
