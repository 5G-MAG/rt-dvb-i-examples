#!/bin/bash
# License: 5G-MAG Public License (v1.0)
# Authors: Jordi J. Gimenez (5G-MAG)
# Copyright: (C) 2026 5G-MAG Association
#
# For full license terms please see the LICENSE file distributed with this
# program. If this file is missing then the license can be retrieved from
# https://www.5g-mag.com/license

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

save_provider_state
log "generating the service list from $(basename "$CHANNELS_FILE")"
./write-service-list.py

if is_running rt-dvb-i-application-provider; then
    pid=$(cat "$PID_DIR/rt-dvb-i-application-provider.pid")
    kill "$pid" 2>/dev/null || true
    for _ in $(seq 1 20); do kill -0 "$pid" 2>/dev/null || break; sleep 0.5; done
    rm -f "$PID_DIR/rt-dvb-i-application-provider.pid"
    log "admin stopped (pid $pid)"
fi

# PLAIN_HTTP: see ADMIN_PLAIN_HTTP in env.sh.
run_bg rt-dvb-i-application-provider env PORT="$ADMIN_PORT" PLAIN_HTTP="$ADMIN_PLAIN_HTTP" node "$ADMIN_DIR/server.js"
wait_http "http://127.0.0.1:$ADMIN_PORT/service-list.xml" 20 || die "the admin did not come back up, see $LOG_DIR/rt-dvb-i-application-provider.log"
log "service list republished: $ADMIN_ORIGIN/service-list.xml"
log "the client re-reads it within 30s (its own poll interval), or reload the page"
