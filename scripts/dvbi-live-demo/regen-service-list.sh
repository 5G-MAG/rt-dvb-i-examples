#!/bin/bash
# Regenerates the admin's service list from channels.json and restarts the admin.
#
# The restart is the point of this script: rt-dvb-i-application-provider/server.js reads config.json once at
# startup into a module-level `config`, so rewriting that file while the admin runs changes
# nothing that a client can see. Use this after editing channels.json.
#
# Editing the line-up in the admin's own UI instead writes config.json through the admin itself
# and needs no restart, but the next run of this script overwrites those edits from channels.json.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source env.sh
source lib.sh
ensure_dirs

log "generating the service list from $(basename "$CHANNELS_FILE")"
./write-service-list.py

if is_running rt-dvb-i-application-provider; then
    pid=$(cat "$PID_DIR/rt-dvb-i-application-provider.pid")
    kill "$pid" 2>/dev/null || true
    for _ in $(seq 1 20); do kill -0 "$pid" 2>/dev/null || break; sleep 0.5; done
    rm -f "$PID_DIR/rt-dvb-i-application-provider.pid"
    log "admin stopped (pid $pid)"
fi

run_bg rt-dvb-i-application-provider env PORT="$ADMIN_PORT" node "$ADMIN_DIR/server.js"
wait_http "http://127.0.0.1:$ADMIN_PORT/service-list.xml" 20 || die "the admin did not come back up, see $LOG_DIR/rt-dvb-i-application-provider.log"
log "service list republished: $ADMIN_ORIGIN/service-list.xml"
log "the client re-reads it within 30s (its own poll interval), or reload the page"
