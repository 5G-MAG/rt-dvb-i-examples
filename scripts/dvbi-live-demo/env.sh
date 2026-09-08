#!/bin/bash
# Shared configuration for the DVB-I live demo scripts. Source this file, do not execute it.
#
# Paths default to this development machine's checkout layout. A clone that lives elsewhere
# needs REPOS_ROOT and CONTENT_ROOT changed; everything else is derived from those two.

set -a

# ------------------------------------------------------------------------------------
# Repository and content locations
# ------------------------------------------------------------------------------------
REPOS_ROOT="${REPOS_ROOT:-$HOME/Repos}"
DVBI_ROOT="${DVBI_ROOT:-$REPOS_ROOT/DVB-I}"
ADMIN_DIR="${ADMIN_DIR:-$DVBI_ROOT/rt-dvb-i-application-provider}"
CLIENT_DIR="${CLIENT_DIR:-$DVBI_ROOT/rt-dvb-i-application}"

# The media origin and the looping live encoder are taken from rt-mbs-examples rather than
# reimplemented here. Only its server side is used: no 5G core, no MBSF/MBSTF, no RAN and no
# MBS client take part in this demo, and none needs to be built for it.
MBS_EXAMPLES_ROOT="${MBS_EXAMPLES_ROOT:-$REPOS_ROOT/rt-mbs/rt-mbs-examples}"
MEDIA_DIR="${MEDIA_DIR:-$MBS_EXAMPLES_ROOT/express-mock-media-server}"
LIVE_ENCODER="${LIVE_ENCODER:-$MBS_EXAMPLES_ROOT/scripts/mbs-broadcast-demo/live-encoder.sh}"

# Source media. Read-only: the scripts play from here and never write into it.
CONTENT_ROOT="${CONTENT_ROOT:-$HOME/MWC_TV_RADIO}"

# ------------------------------------------------------------------------------------
# Ports. All three services bind loopback only.
# ------------------------------------------------------------------------------------
MEDIA_HOST="${MEDIA_HOST:-127.0.0.1}"
MEDIA_PORT="${MEDIA_PORT:-3004}"
ADMIN_PORT="${ADMIN_PORT:-4000}"
CLIENT_PORT="${CLIENT_PORT:-5000}"

MEDIA_ORIGIN="http://$MEDIA_HOST:$MEDIA_PORT"
ADMIN_ORIGIN="http://localhost:$ADMIN_PORT"
CLIENT_ORIGIN="http://localhost:$CLIENT_PORT"

# ------------------------------------------------------------------------------------
# Encoding
# ------------------------------------------------------------------------------------
# Segment duration in seconds. Also becomes the MPD's own @minimumUpdatePeriod, so a shorter
# value means the receiver re-reads the manifest more often and joins closer to the live edge,
# at the cost of more requests.
LIVE_SEG_DURATION="${LIVE_SEG_DURATION:-4}"

# ------------------------------------------------------------------------------------
# Run-time state: logs and pidfiles under this script directory's own run/, not /tmp.
# ------------------------------------------------------------------------------------
DEMO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_DIR="$DEMO_ROOT/run"
LOG_DIR="$RUN_DIR/logs"
PID_DIR="$RUN_DIR/pids"
CHANNELS_FILE="${CHANNELS_FILE:-$DEMO_ROOT/channels.json}"

# The receiver's /proxy refuses to fetch from loopback and private addresses (its own SSRF guard),
# which is exactly where the provider sits in this demo. PROXY_ALLOW_ORIGINS names the origins it
# may fetch anyway, matched exactly on scheme, host and port, leaving every other address guarded.
#
# Both spellings of the provider's origin are needed: the receiver loads the service list from
# localhost:4000, while the ContentGuideSource inside that list points at 127.0.0.1:4000, and an
# allowlist entry is an origin rather than a host.
PROXY_ALLOW_ORIGINS="${PROXY_ALLOW_ORIGINS:-http://localhost:$ADMIN_PORT,http://127.0.0.1:$ADMIN_PORT}"

set +a
