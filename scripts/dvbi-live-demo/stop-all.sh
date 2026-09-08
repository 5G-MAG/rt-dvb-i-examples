#!/bin/bash
# Stops everything start-all.sh started, and nothing else.
#
# Each pidfile holds the process this demo started directly. The encoders are ffmpeg itself:
# live-encoder.sh ends in `exec ffmpeg`, so the recorded pid is the encoder, not a wrapper that
# would leave ffmpeg orphaned behind it.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source env.sh
source lib.sh

stopped=0
for pidfile in "$PID_DIR"/*.pid; do
    [[ -e "$pidfile" ]] || continue
    name=$(basename "$pidfile" .pid)
    pid=$(cat "$pidfile")
    if kill "$pid" 2>/dev/null; then
        log "stopped $name (pid $pid)"
        stopped=$((stopped + 1))
    else
        log "$name was not running (stale pidfile)"
    fi
    rm -f "$pidfile"
done

# A port left bound after that means an instance started outside these scripts, by hand or by an
# earlier session whose pidfiles are gone. Report it rather than killing it: this script does not
# know what else on this machine may be using that port.
for port in "$MEDIA_PORT" "$ADMIN_PORT" "$CLIENT_PORT"; do
    pid=$(port_pid "$port")
    if [[ -n "$pid" ]]; then
        warn "port $port is still bound by pid $pid, which this demo did not start. Leaving it alone."
        warn "  inspect it with: ps -p $pid -o pid,cmd"
    fi
done

log "$stopped process(es) stopped"
