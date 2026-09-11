<h1 align="center">DVB-I Examples</h1>
<p align="center">
  <img src="https://img.shields.io/badge/Status-Under_Development-yellow" alt="Under Development">
</p>

## Introduction

Runnable example setups for the DVB-I pair:

- **`rt-dvb-i-application-provider`** publishes a DVB-I service list (the Application Provider and
  admin portal)
- **`rt-dvb-i-application`** discovers that list and plays the channels in it (the receiver)
- **`rt-dvb-i-service-list-registry`** tells a receiver which service lists exist (discovery)

Each example brings the two up against real content, so the pair can be exercised end to end
without a broadcaster's service list or a public CDN.

## Running the demo

**Before the first run**, once per machine: Node 18 or newer, ffmpeg, python3 and curl, plus the
DVB-I application and provider checked out and installed beside this repository. The full list is
in [the demo's Prerequisites](scripts/dvbi-live-demo/README.md#0-prerequisites).

After that, every run is the four commands below.

```bash
./demo doctor              # will it start here? changes nothing
./demo up
./demo status
./demo down                # stops it and verifies nothing of it is left
./demo down --all          # stops all three demos, in every repository it can find
```

`./demo up` runs the checks first and refuses to start on a conflict, naming what to stop. The
check that matters here is the media origin: this demo runs its own copy of rt-mbs-examples'
`express-mock-media-server` on port 3004, and the MBS demo in that repository binds the same port
for its own origin, so the two cannot both be up.

| | this repository | rt-mbs-examples | rt-mbms-examples |
|---|---|---|---|
| media origin | :3004 | **:3004, same as this one** | :3005 |
| admin / client | :4000, :5000 | :8091, :3050 | :8080, :3000 |
| radio | none | ZMQ 2100, 2101 | ZMQ 2100, 2101 |

The two radio-bearing demos do not take this one's ports, but they are large enough to matter for
memory, so `doctor` mentions them. Restarting this demo while it is already up is fine and is not
treated as a conflict, because `start-all.sh` stops it first.

`./demo down` does not trust the stop script. It runs it, then checks this demo's processes and
ports are actually gone and clears anything left, so the next run starts from nothing. `--all`
does the same for the other two demos, finding their checkouts beside this one; set
`MBS_EXAMPLES_DIR` or `MBMS_EXAMPLES_DIR` if they live somewhere unusual.

Add `--force` to `up` to start anyway. `DEMO_MIN_FREE_MB` overrides the memory floor.

The scripts under `scripts/dvbi-live-demo/` are unchanged and can still be run directly.

### Demo content

Content starts with the demo. `./demo up` launches one looping ffmpeg encoder per channel and
publishes a DVB-I service list describing them, so there is nothing extra to run.

The source clips live in `~/MWC_TV_RADIO/` (`TV_1.mp4`, `RADIO.mp4` and their logos), set by
`CONTENT_ROOT`. That directory is required: without it the encoders have nothing to loop and the
client shows an empty list.

```bash
# check content is actually flowing, once the demo is up
./demo status                       # per channel: LIVE, how long ago it last published, segments
curl -s http://localhost:4000/service-list.xml | head
```

The three channels are defined in `scripts/dvbi-live-demo/channels.json`: logical channel number,
name, logo and source clip. After editing it:

```bash
scripts/dvbi-live-demo/regen-service-list.sh    # rebuild the service list from channels.json
```

Open the client at http://localhost:5000 and the admin at http://localhost:4000.

## Start here

- **[Running the pair, end to end](docs/running-the-pair.md)** -- the two applications from a clean
  checkout against public test streams: install, start each, publish a change and watch it reach the
  receiver, run the test suites. Read this first if you have not run them before.

## Assessments

- **DVB-I over 5G** -- what carrying these services over a 5G system would require: what the
  standards already specify (more than expected), what is still missing from them, and which of the
  missing pieces these repositories could supply. It lives with the conformance record it belongs
  beside, in `rt-dvb-i-application-provider/DVB-I-OVER-5G.md`, rather than being copied here where
  the two would drift apart.

## Examples

- **[DVB-I live demo](scripts/dvbi-live-demo/README.md)** -- publishes a service list of your own
  channels, encoded live and on repeat from your own media files, and plays them in the receiver.
  Unicast DASH over HTTP from a local origin. Nothing leaves the machine and no external stream is
  involved. The README is the full reproduction procedure, start to finish.

## What this reuses, and what it does not

The media origin and the looping live encoder come from
[rt-mbs-examples](https://github.com/5G-MAG/rt-mbs-examples): `express-mock-media-server` and
`scripts/mbs-broadcast-demo/live-encoder.sh`. Only that server side is used.

Nothing from the 5G stack takes part. There is no multicast, no core network, no MBSF or MBSTF, no
gNB or UE and no MBS client, and none of them needs to be built. What is exercised here is DVB-I
service discovery and playback over unicast HTTP.

That makes this the DVB-I counterpart to the MBS broadcast tutorial rather than a variant of it.
The same content can be carried either way, and running both shows the difference.

## Requirements

- Node.js 18 or newer, and npm
- ffmpeg
- python3 and curl
- checkouts of `rt-dvb-i-application-provider`, `rt-dvb-i-application` and `rt-mbs-examples`
  (paths are set in each example's `env.sh`)
- your own media files to broadcast

## Checking citations

Comments across these repositories cite clauses of the DVB-I specification and of its
implementation guidelines. Both documents number clauses in the same ranges, so a citation naming
no document is resolved by a reader against whichever they assume, and that has produced real
errors: comments citing implementation guidance for behaviour the specification governs, and
clauses that turned out to cover something else.

```bash
DVBI_SPECS=~/.local/share/dvb-i-specs tools/verify-citations.py
```

It checks that every citation names its document and that the clause exists there. Supply the two
documents yourself as plain text, outside every working tree: no specification text is carried in
these repositories. Without them the check skips. It cannot tell you whether a clause says what a
comment claims; only reading does that.

## Layout

```
scripts/dvbi-live-demo/   the live demo: channel line-up, start/stop/status, service list generator
tools/                    the citation checker
backups/                  the provider's service list as it was before an example first replaced it
```
