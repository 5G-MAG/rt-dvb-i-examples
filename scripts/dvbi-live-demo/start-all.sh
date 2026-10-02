#!/bin/bash
# Brings up the DVB-I demo: a local live DASH origin, the DVB-I admin publishing a service list
# that points at it, and the DVB-I client playing from that list.
#
# What it starts, in order:
#   1. the media origin, rt-media-origin, configured from channels.json: it runs one looping
#      live encoder (ffmpeg) per channel itself
#   2. the DVB-I admin, after writing its service list from those same channels
#   3. the Service List Registry
#   4. the DVB-I client
#
# Nothing from the 5G stack takes part: no core network functions, no MBSF/MBSTF, no gNB or UE,
# no MBS client, and none of them needs to be built. The path under test here is DVB-I over
# unicast HTTP.
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
    require_cmd ffprobe "Install it: apt install ffmpeg"
    for f in ContentCS.xml FormatCS.xml DVBContentSubjectCS-2019.xml; do
        [[ -f "$GENRE_CS_DIR/$f" ]] || die "the registry needs $GENRE_CS_DIR/$f (set GENRE_CS_DIR in env.sh; the scheme files are not bundled, see the demo README)"
    done
    [[ -f "$MEDIA_ORIGIN_DIR/bin/www" ]] || die "rt-media-origin not found at $MEDIA_ORIGIN_DIR (set MEDIA_ORIGIN_DIR in env.sh)"
    # Radio services are served as audio-only channels, which rt-media-origin accepts only from its
    # audioOnly support onwards; an older checkout would refuse the generated config at start-up.
    if grep -q '"type": *"radio"' "$CHANNELS_FILE" && ! grep -q '"audioOnly"' "$MEDIA_ORIGIN_DIR/config/config.schema.json"; then
        die "rt-media-origin at $MEDIA_ORIGIN_DIR has no audio-only channels, which the radio service needs (use a checkout with audioOnly support, or leave radio out with DEMO_CHANNELS)"
    fi
    for d in "$ADMIN_DIR" "$CLIENT_DIR" "$REGISTRY_DIR"; do
        [[ -d "$d" ]] || die "not found: $d (check the paths in env.sh)"
    done
    while IFS='|' read -r id name lcn source stream; do
        [[ -f "$CONTENT_ROOT/$source" ]] || die "missing source media for $id: $CONTENT_ROOT/$source"
    done < <(channel_lines)
    # rt-media-origin ships a package-lock.json, so its dependencies are installed exactly as
    # locked, without rewriting the lockfile in a checkout this demo does not own.
    [[ -d "$MEDIA_ORIGIN_DIR/node_modules" ]] || { log "installing dependencies in $MEDIA_ORIGIN_DIR"; (cd "$MEDIA_ORIGIN_DIR" && npm ci --no-audit --no-fund); }
    for d in "$ADMIN_DIR" "$CLIENT_DIR" "$REGISTRY_DIR"; do
        [[ -d "$d/node_modules" ]] || { log "installing dependencies in $d"; (cd "$d" && npm install --no-audit --no-fund); }
    done
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
# The provider's config.json and logos are about to be overwritten; stop-all.sh restores them.
save_provider_state

log "=== 1/4 media origin (rt-media-origin) ==="
log "generating its configuration from $(basename "$CHANNELS_FILE")"
./write-origin-config.py
# PORT and HOST are passed as well as written into the configuration: rt-media-origin lets them
# override the file (src/config/loadConfig.js), so a PORT left in the caller's environment would
# otherwise move the origin away from the address the service list names.
run_bg rt-media-origin env RT_MEDIA_SERVER_CONFIG="$ORIGIN_CONFIG" PORT="$MEDIA_PORT" HOST="$MEDIA_HOST" \
    node "$MEDIA_ORIGIN_DIR/bin/www"
wait_http "$MEDIA_ORIGIN/healthz" 20 || die "the media origin did not come up, see $LOG_DIR/rt-media-origin.log"

log "waiting for each presentation to become servable"
while IFS='|' read -r id name lcn source stream; do
    wait_presentation "$stream" 120 || die "no usable manifest for $stream, see $LOG_DIR/rt-media-origin.log (lines prefixed [$id])"
    log "  $stream ready"
done < <(channel_lines)

log "=== 2/4 DVB-I Application Provider ==="
# Written before the admin starts: it reads config.json once at startup (rt-dvb-i-application-provider/server.js
# loads it into a module-level `config`), so a list generated afterwards would not be served
# until the admin is restarted. Use ./regen-service-list.sh for that case.
install_logos
log "generating the service list from $(basename "$CHANNELS_FILE")"
./write-service-list.py
# PLAIN_HTTP: see ADMIN_PLAIN_HTTP in env.sh.
run_bg rt-dvb-i-application-provider env PORT="$ADMIN_PORT" PLAIN_HTTP="$ADMIN_PLAIN_HTTP" node "$ADMIN_DIR/server.js"
wait_http "http://127.0.0.1:$ADMIN_PORT/service-list.xml" 20 || die "the admin did not come up, see $LOG_DIR/rt-dvb-i-application-provider.log"

log "=== 3/4 Service List Registry ==="
# Started before the receiver so discovery can be answered the moment a viewer opens the page.
# It lists the provider's service list, which is how a client gets from "which lists exist?" to
# a URL without one being typed in.
run_bg rt-dvb-i-service-list-registry env PORT="$REGISTRY_PORT" GENRE_CS_DIR="$GENRE_CS_DIR" node "$REGISTRY_DIR/server.js"
wait_http "$REGISTRY_ORIGIN/health" 20 || die "the registry did not come up, see $LOG_DIR/rt-dvb-i-service-list-registry.log"

log "=== 4/4 DVB-I client ==="
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
echo "  Media origin               ->  $MEDIA_ORIGIN/healthz"
echo
echo "  ./status.sh   what is running, and whether each presentation is advancing"
echo "  ./stop-all.sh stop everything this script started"
