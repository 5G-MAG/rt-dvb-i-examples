#!/bin/bash
# Brings up the DVB-I demo: a local live DASH origin, the DVB-I admin publishing a service list
# that points at it, and the DVB-I client playing from that list.
#
# What it starts, in order:
#   1. the media origin (rt-mbs-examples/express-mock-media-server)
#   2. one looping live encoder per channel in channels.json
#   3. the DVB-I admin, after writing its service list from those same channels
#   4. the DVB-I client
#
# Only the server side of the MBS broadcast demo is used. Nothing from the 5G stack takes part:
# no core network functions, no MBSF/MBSTF, no gNB or UE, no MBS client, and none of them needs
# to be built. The path under test here is DVB-I over unicast HTTP.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source env.sh
source lib.sh
ensure_dirs

# Everything the run needs is checked before anything is started, so a missing prerequisite
# fails in seconds rather than part-way through, leaving half the demo running.
preflight() {
    require_cmd ffmpeg  "Install it: apt install ffmpeg"
    require_cmd node    "Node 18 or newer is required."
    require_cmd npm     "Node 18 or newer is required."
    require_cmd curl    "Install it: apt install curl"
    require_cmd python3 "Install it: apt install python3"
    [[ -d "$CONTENT_ROOT" ]] || die "content not found: $CONTENT_ROOT (set CONTENT_ROOT in env.sh)"
    [[ -f "$LIVE_ENCODER" ]] || die "live encoder not found: $LIVE_ENCODER (set MBS_EXAMPLES_ROOT in env.sh)"
    for d in "$MEDIA_DIR" "$ADMIN_DIR" "$CLIENT_DIR" "$REGISTRY_DIR"; do
        [[ -d "$d" ]] || die "not found: $d (check the paths in env.sh)"
    done
    while IFS='|' read -r id name lcn source stream; do
        [[ -f "$CONTENT_ROOT/$source" ]] || die "missing source media for $id: $CONTENT_ROOT/$source"
    done < <(channel_lines)
    for d in "$MEDIA_DIR" "$ADMIN_DIR" "$CLIENT_DIR" "$REGISTRY_DIR"; do
        [[ -d "$d/node_modules" ]] || { log "installing dependencies in $d"; (cd "$d" && npm install --no-audit --no-fund); }
    done
}

# The admin's line-up lives in its own config.json, which is tracked in the rt-dvb-i-application-provider
# repository. Keep the shipped one before overwriting it, so the demo can be undone on a
# checkout where `git checkout config.json` is not wanted or no longer restores it.
backup_admin_config() {
    local backup="$DEMO_ROOT/../../backups/rt-dvb-i-application-provider-config.json.pre-demo"
    if [[ ! -f "$backup" ]]; then
        mkdir -p "$(dirname "$backup")"
        cp "$ADMIN_DIR/config.json" "$backup"
        log "kept the admin's previous service list at $backup"
    fi
}

# Channel logos are the operator's own artwork, so they are read from CONTENT_ROOT rather than
# carried in this repository. A channel with no logo file simply keeps the admin's own generated
# lettered logo.
install_logos() {
    local dest="$ADMIN_DIR/public/logos/uploaded"
    mkdir -p "$dest"
    python3 - "$CHANNELS_FILE" "$CONTENT_ROOT" "$dest" <<'PYEOF'
import json, os, shutil, sys
channels_file, content_root, dest = sys.argv[1:4]
for c in json.load(open(channels_file))["channels"]:
    logo = c.get("logo")
    if not logo:
        continue
    src = os.path.join(content_root, logo)
    if not os.path.isfile(src):
        print(f"  no logo file for {c['id']} at {src}, the admin will generate a lettered one")
        continue
    shutil.copyfile(src, os.path.join(dest, f"{c['id']}.png"))
    print(f"  logo installed for {c['id']}")
PYEOF
}

preflight
backup_admin_config

log "=== 1/5 local media origin ==="
run_bg media-server env HOST="$MEDIA_HOST" PORT="$MEDIA_PORT" node "$MEDIA_DIR/bin/www"
wait_http_any "$MEDIA_ORIGIN/" 20 || die "the media origin did not come up, see $LOG_DIR/media-server.log"

log "=== 2/5 live encoders ==="
while IFS='|' read -r id name lcn source stream; do
    run_bg "encoder-$id" env \
        LIVE_SRC="$CONTENT_ROOT/$source" \
        LIVE_STREAM_NAME="$stream" \
        LIVE_SEG_DURATION="$LIVE_SEG_DURATION" \
        "$LIVE_ENCODER"
done < <(channel_lines)

log "waiting for each presentation to become servable"
while IFS='|' read -r id name lcn source stream; do
    wait_presentation "$stream" 120 || die "no usable manifest for $stream, see $LOG_DIR/encoder-$id.log"
    log "  $stream ready"
done < <(channel_lines)

log "=== 3/5 DVB-I Application Provider ==="
# Written before the admin starts: it reads config.json once at startup (rt-dvb-i-application-provider/server.js
# loads it into a module-level `config`), so a list generated afterwards would not be served
# until the admin is restarted. Use ./regen-service-list.sh for that case.
install_logos
log "generating the service list from $(basename "$CHANNELS_FILE")"
./write-service-list.py
run_bg rt-dvb-i-application-provider env PORT="$ADMIN_PORT" node "$ADMIN_DIR/server.js"
wait_http "http://127.0.0.1:$ADMIN_PORT/service-list.xml" 20 || die "the admin did not come up, see $LOG_DIR/rt-dvb-i-application-provider.log"

log "=== 4/5 Service List Registry ==="
# Started before the receiver so discovery can be answered the moment a viewer opens the page.
# It lists the provider's service list, which is how a client gets from "which lists exist?" to
# a URL without one being typed in.
run_bg rt-dvb-i-service-list-registry env PORT="$REGISTRY_PORT" node "$REGISTRY_DIR/server.js"
wait_http "$REGISTRY_ORIGIN/health" 20 || die "the registry did not come up, see $LOG_DIR/rt-dvb-i-service-list-registry.log"

log "=== 5/5 DVB-I client ==="
# PROXY_ALLOW_ORIGINS: see the note on it in env.sh. Without it the receiver's /proxy refuses to
# fetch the service list, because the provider is on loopback.
run_bg rt-dvb-i-application env PORT="$CLIENT_PORT" PROXY_ALLOW_ORIGINS="$PROXY_ALLOW_ORIGINS" node "$CLIENT_DIR/server.js"
wait_http "http://127.0.0.1:$CLIENT_PORT/health" 20 || die "the client did not come up, see $LOG_DIR/rt-dvb-i-application.log"

echo
log "up:"
echo "  DVB-I client (open this)   ->  $CLIENT_ORIGIN"
echo "  Application Provider       ->  $ADMIN_ORIGIN"
echo "  Service List Registry      ->  $REGISTRY_ORIGIN/query?TargetCountry=CHE"
echo "  Service list               ->  $ADMIN_ORIGIN/service-list.xml"
echo "  Local origin               ->  $MEDIA_ORIGIN/"
echo
echo "  ./status.sh   what is running, and whether each presentation is advancing"
echo "  ./stop-all.sh stop everything this script started"
