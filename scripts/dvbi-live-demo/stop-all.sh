#!/bin/bash
# License: 5G-MAG Public License (v1.0)
# Authors: Jordi J. Gimenez (5G-MAG)
# Copyright: (C) 2026 5G-MAG Association
#
# For full license terms please see the LICENSE file distributed with this
# program. If this file is missing then the license can be retrieved from
# https://www.5g-mag.com/license

# Stops everything start-all.sh started, and nothing else.
#
# Each pidfile holds the process this demo started directly. The encoders are not among them:
# rt-media-origin spawns one ffmpeg per channel itself and stops them on SIGTERM before it exits.
# Its children are therefore noted before it is signalled, and the stop waits for them as well as
# for it, so an encoder left behind is reported and cleared rather than left writing segments.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source env.sh
source lib.sh

stopped=0
for pidfile in "$PID_DIR"/*.pid; do
    [[ -e "$pidfile" ]] || continue
    name=$(basename "$pidfile" .pid)
    pid=$(cat "$pidfile")
    children=$(pgrep -P "$pid" 2>/dev/null | paste -sd' ')
    if kill "$pid" 2>/dev/null; then
        for _ in $(seq 1 20); do
            alive=0
            for p in $pid $children; do kill -0 "$p" 2>/dev/null && alive=1; done
            (( alive )) || break
            sleep 0.5
        done
        for p in $pid $children; do
            if kill -0 "$p" 2>/dev/null; then
                warn "$name: pid $p did not exit within 10s of SIGTERM, killing it"
                kill -KILL "$p" 2>/dev/null || true
            fi
        done
        log "stopped $name (pid $pid${children:+, and its children $children})"
        stopped=$((stopped + 1))
    else
        log "$name was not running (stale pidfile)"
    fi
    rm -f "$pidfile"
done

# Only once the provider has stopped, so it cannot write config.json again after the restore.
restore_provider_state

# A port left bound after that means an instance started outside these scripts, by hand or by an
# earlier session whose pidfiles are gone. Report it rather than killing it: this script does not
# know what else on this machine may be using that port.
for port in "$MEDIA_PORT" "$ADMIN_PORT" "$CLIENT_PORT" "$REGISTRY_PORT"; do
    pid=$(port_pid "$port")
    if [[ -n "$pid" ]]; then
        warn "port $port is still bound by pid $pid, which this demo did not start. Leaving it alone."
        warn "  inspect it with: ps -p $pid -o pid,cmd"
    fi
done

log "$stopped process(es) stopped"
