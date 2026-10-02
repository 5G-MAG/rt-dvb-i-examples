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
REGISTRY_DIR="${REGISTRY_DIR:-$DVBI_ROOT/rt-dvb-i-service-list-registry}"

# The media origin is rt-media-origin: one process that loops each channel's source with its own
# ffmpeg, packages it as live DASH and serves it. Its configuration is generated from
# channels.json into this demo's run/ directory (write-origin-config.py); nothing is written into
# the rt-media-origin checkout.
MEDIA_ORIGIN_DIR="${MEDIA_ORIGIN_DIR:-$REPOS_ROOT/rt-media-origin}"

# Source media. Read-only: the scripts play from here and never write into it.
CONTENT_ROOT="${CONTENT_ROOT:-$HOME/MWC_TV_RADIO}"

# ------------------------------------------------------------------------------------
# Ports. All three services bind loopback only.
# ------------------------------------------------------------------------------------
MEDIA_HOST="${MEDIA_HOST:-127.0.0.1}"
MEDIA_PORT="${MEDIA_PORT:-3004}"
ADMIN_PORT="${ADMIN_PORT:-4000}"
CLIENT_PORT="${CLIENT_PORT:-5000}"

# The Service List Registry: the component a client asks which service lists exist, so the demo can
# show discovery rather than starting from a URL somebody typed in.
REGISTRY_PORT="${REGISTRY_PORT:-7000}"

MEDIA_ORIGIN="http://$MEDIA_HOST:$MEDIA_PORT"
ADMIN_ORIGIN="http://localhost:$ADMIN_PORT"
CLIENT_ORIGIN="http://localhost:$CLIENT_PORT"
REGISTRY_ORIGIN="http://localhost:$REGISTRY_PORT"

# ------------------------------------------------------------------------------------
# Encoding
# ------------------------------------------------------------------------------------
# Segment duration in seconds. Also becomes the MPD's own @minimumUpdatePeriod, so a shorter
# value means the receiver re-reads the manifest more often and joins closer to the live edge,
# at the cost of more requests.
LIVE_SEG_DURATION="${LIVE_SEG_DURATION:-4}"

# Segments the live manifest advertises, and segments kept on disk beyond that for requests still
# in flight. rt-media-origin deletes anything older, so a channel left running does not fill the
# disk. Defaults carried over from the encoder this demo used before (live-encoder.sh).
LIVE_WINDOW="${LIVE_WINDOW:-24}"
LIVE_EXTRA_WINDOW="${LIVE_EXTRA_WINDOW:-48}"

# Video bit rate of every channel's single 960x540 H.264 rendition. An operator setting, no clause
# governs it; the default is the previous encoder's.
LIVE_VIDEO_BITRATE="${LIVE_VIDEO_BITRATE:-400k}"

# ------------------------------------------------------------------------------------
# Run-time state: logs and pidfiles under this script directory's own run/, not /tmp.
# ------------------------------------------------------------------------------------
DEMO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_DIR="$DEMO_ROOT/run"
LOG_DIR="$RUN_DIR/logs"
PID_DIR="$RUN_DIR/pids"
CHANNELS_FILE="${CHANNELS_FILE:-$DEMO_ROOT/channels.json}"
# The generated rt-media-origin configuration, and the directories its channels write into.
ORIGIN_CONFIG="$RUN_DIR/origin/config.json"
ORIGIN_OUTPUT_ROOT="$RUN_DIR/origin/media"
# The provider's own files as they were before this demo first wrote over them: its config.json
# and any channel logos install_logos (start-all.sh) replaces. stop-all.sh puts them back.
PROVIDER_SAVED_DIR="$RUN_DIR/provider-saved"

# What the provider is told about TLS. Without HTTPS_KEY_PATH and HTTPS_CERT_PATH it serves plain
# HTTP; an earlier issue of rt-dvb-i-application-provider refused to do so unless PLAIN_HTTP named
# the case, and the current one accepts "private-subnet" as meaning the same as leaving it unset.
# Passed to the provider only (start-all.sh, regen-service-list.sh), under its own name here so
# that exporting it does not hand PLAIN_HTTP to every other process.
ADMIN_PLAIN_HTTP="${ADMIN_PLAIN_HTTP:-private-subnet}"

# The registry refuses to start without GENRE_CS_DIR: a directory holding the classification
# schemes its Genre query values are checked against, ContentCS.xml and FormatCS.xml (TV-Anytime)
# and DVBContentSubjectCS-2019.xml (from the TS 103 770 attachment archive). They are never
# carried in these repositories; see the registry's README for where each comes from.
GENRE_CS_DIR="${GENRE_CS_DIR:-$HOME/.local/share/dvb-i-schemas/etsi}"

# The receiver's /proxy refuses to fetch from loopback and private addresses (its own SSRF guard),
# which is exactly where the provider sits in this demo. PROXY_ALLOW_ORIGINS names the origins it
# may fetch anyway, matched exactly on scheme, host and port, leaving every other address guarded.
#
# Both spellings of the provider's origin are needed: the receiver loads the service list from
# localhost:4000, while the ContentGuideSource inside that list points at 127.0.0.1:4000, and an
# allowlist entry is an origin rather than a host.
# The registry's origin is named too: the receiver reaches it through the same guarded proxy, so
# discovery fails with a 400 if it is left out.
PROXY_ALLOW_ORIGINS="${PROXY_ALLOW_ORIGINS:-http://localhost:$ADMIN_PORT,http://127.0.0.1:$ADMIN_PORT,http://localhost:$REGISTRY_PORT,http://127.0.0.1:$REGISTRY_PORT}"

set +a
