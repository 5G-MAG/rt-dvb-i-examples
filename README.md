<p align="center">
  <img src=".github/banner.svg" width="100%" alt="Reference Tools · DVB-I Services over 5G Systems: DVB-I Examples">
</p>

<p align="center">
  Runnable examples that bring the DVB-I repositories up together on one machine, publishing and
  playing a service list per ETSI TS 103 770.
</p>

<p align="center">
  <img alt="Status: under development"
    src="https://img.shields.io/badge/Status-Under_Development-yellow">
  <a href="https://github.com/5G-MAG/rt-dvb-i-examples/releases"><img alt="Version"
    src="https://img.shields.io/github/v/release/5G-MAG/rt-dvb-i-examples?label=Version&sort=semver"></a>
  <a href="LICENSE"><img alt="License: 5G-MAG Public License v1.0"
    src="https://img.shields.io/badge/License-5G--MAG%20PL%20v1.0-blue"></a>
</p>

<p align="center">
  <a href="https://www.5g-mag.com/reference-tools/dvb-i">Project page</a> &nbsp;&middot;&nbsp;
  <a href="https://github.com/5G-MAG/rt-dvb-i-examples/issues">Issues</a> &nbsp;&middot;&nbsp;
  <a href="https://www.5g-mag.com/contributing">Contributing</a>
</p>

---

## At a glance

|  |  |
|---|---|
| **Implements** | ETSI TS 103 770 V1.2.1 (2024-09), *Digital Video Broadcasting (DVB); Service Discovery and Programme Metadata for DVB-I* |
| **Part of** | [DVB-I Services over 5G Systems](https://www.5g-mag.com/reference-tools/dvb-i), alongside [rt-dvb-i-application](https://github.com/5G-MAG/rt-dvb-i-application), [rt-dvb-i-android-application](https://github.com/5G-MAG/rt-dvb-i-android-application), [rt-dvb-i-application-provider](https://github.com/5G-MAG/rt-dvb-i-application-provider), [rt-dvb-i-service-list-registry](https://github.com/5G-MAG/rt-dvb-i-service-list-registry) and [rt-5gms-application](https://github.com/5G-MAG/rt-5gms-application) |

## Introduction

Runnable example setups for the DVB-I repositories:

- **`rt-dvb-i-application-provider`** publishes a DVB-I service list (the Application Provider and
  admin portal)
- **`rt-dvb-i-application`** discovers that list and plays the channels in it (the receiver)
- **`rt-dvb-i-android-application`** does the same on an Android phone, over the same Wi-Fi (see
  `scripts/dvbi-live-demo`, section 3a)
- **`rt-dvb-i-service-list-registry`** tells a receiver which service lists exist (discovery)

Each example brings them up against real content, so they can be exercised end to end without a
broadcaster's service list or a public CDN.

### What this reuses, and what it does not

The media origin is [rt-media-origin](https://github.com/5G-MAG/rt-media-origin), configured from
the demo's `channels.json`. It loops each channel's source with its own ffmpeg, packages it as live
DASH and serves it.

Nothing from the 5G stack takes part. There is no multicast, no core network, no MBSF or MBSTF, no
gNB or UE and no MBS client, and none of them needs to be built. What is exercised here is DVB-I
service discovery and playback over unicast HTTP.

That makes this the DVB-I counterpart to the MBS broadcast tutorial rather than a variant of it.
The same content can be carried either way, and running both shows the difference.

## Specification

The demo's service list generator targets **ETSI TS 103 770 V1.2.1 (2024-09)**, a version rather
than a release name.

Clause-by-clause coverage, and what is still absent, is recorded on the project page rather than
here: <https://www.5g-mag.com/reference-tools/dvb-i>

**DVB-I over 5G.** What carrying these services over a 5G system would require (what the standards
already specify, what is still missing from them, and which of the missing pieces these
repositories could supply) is assessed in `rt-dvb-i-application-provider/DVB-I-OVER-5G.md`. It
lives there, beside the conformance record it belongs to, rather than being copied here where the
two would drift apart.

## Install dependencies

Once per machine:

- Node.js 18 or newer, and npm
- ffmpeg
- python3 and curl
- checkouts of `rt-dvb-i-application-provider`, `rt-dvb-i-application`,
  `rt-dvb-i-service-list-registry` and `rt-media-origin` (paths are set in each example's `env.sh`)
- the Genre classification scheme files the registry needs (`GENRE_CS_DIR`)
- your own media files to broadcast

The DVB-I application and provider must be checked out and installed beside this repository. The
full list, with the expected checkout layout, is in
[the demo's Prerequisites](scripts/dvbi-live-demo/README.md#0-prerequisites).

## Downloading

```bash
cd ~
git clone https://github.com/5G-MAG/rt-dvb-i-examples.git
```

## Running

Start with **[Running the pair, end to end](docs/running-the-pair.md)** if you have not run the
applications before: the two applications from a clean checkout against public test streams,
install, start each, publish a change and watch it reach the receiver, run the test suites.

The **[DVB-I live demo](scripts/dvbi-live-demo/README.md)** publishes a service list of your own
channels, encoded live and on repeat from your own media files, and plays them in the receiver.
Delivery is unicast DASH over HTTP from a local origin. Nothing leaves the machine and no external
stream is involved. Its README is the full reproduction procedure, start to finish; what follows is
the short form.

### Running the demo

Every run is the commands below.

```bash
./demo doctor              # will it start here? changes nothing
./demo up
./demo status
./demo down                # stops it and verifies nothing of it is left
./demo down --all          # stops all three demos, in every repository it can find
```

`./demo up` runs the checks first and refuses to start on a conflict, naming what to stop. The
check that matters here is the media origin: this demo runs rt-media-origin on port 3004, and the
MBS demo in rt-mbs-examples binds the same port for its own origin, so the two cannot both be up.

| | this repository | rt-mbs-examples | rt-mbms-examples |
|---|---|---|---|
| media origin | :3004 | **:3004, same as this one** | :3005 |
| admin / client | :4000, :5000 | :8091, :3050 | :8080, :3000 |
| service list registry | :7000 | none | none |
| radio | none | ZMQ 2100, 2101 | ZMQ 2100, 2101 |

**This demo and the MBMS one can run at the same time.** They share no port, no network namespace
and no process name: this one's origin is rt-media-origin on :3004, the MBMS demo runs
its own `media-server.js` on :3005, and neither `down` can reach the other's processes. Start them
in either order. The only thing they compete for is memory, which is why `doctor` mentions a
neighbouring demo rather than refusing to start. On a machine that is tight, bring up the MBMS one
first, since it is the larger of the two.

The MBS demo is the exception: it takes :3004 for its own origin, so it and this one cannot both
be up. Restarting this demo while it is already up is fine and is not treated as a conflict,
because `start-all.sh` stops it first.

`./demo down` does not trust the stop script. It runs it, then checks that this demo's processes
and ports are actually gone and clears anything left, so the next run starts from nothing. `--all`
does the same for the other two demos, finding their checkouts beside this one.

The scripts under `scripts/dvbi-live-demo/` are unchanged and can still be run directly.

### Demo content

Content starts with the demo. `./demo up` launches one looping ffmpeg encoder per channel and
publishes a DVB-I service list describing them, so there is nothing extra to run.

```bash
# check content is actually flowing, once the demo is up
./demo status                       # per channel: LIVE, how long ago it last published, segments
curl -s http://localhost:4000/service-list.xml | head
```

Open the client at http://localhost:5000 and the admin at http://localhost:4000.

## Configuration

- **Source media.** The clips live in `~/MWC_TV_RADIO/` (`TV_1.mp4` to `TV_3.mp4`, `RADIO.mp4`
  and their logos), set by `CONTENT_ROOT`. That directory is required: without it the encoders have
  nothing to loop and the client shows an empty list.
- **Channel line-up.** The channels are defined in `scripts/dvbi-live-demo/channels.json`: logical
  channel number, name, logo and source clip. `DEMO_CHANNELS` limits a run to the channel ids it
  names. After editing the file, rebuild the service list (below).
- **Paths and ports.** Checkout locations and ports are set in `scripts/dvbi-live-demo/env.sh`.
- **Neighbouring demos.** Set `MBS_EXAMPLES_DIR` or `MBMS_EXAMPLES_DIR` if the other demos' checkouts
  live somewhere unusual, for `./demo down --all`.
- **Start checks.** Add `--force` to `up` to start anyway. `DEMO_MIN_FREE_MB` overrides the memory
  floor.

```bash
scripts/dvbi-live-demo/regen-service-list.sh    # rebuild the service list from channels.json
```

## Development

The service list generator has a unittest suite, `scripts/dvbi-live-demo/test_generator.py`
(32 cases). One case compares the shipped list template with what `channels.json` would produce and
needs the provider checked out beside this repository, and one validates the generated
rt-media-origin configuration with that repository's own validator and needs it checked out with
its dependencies; without them, those cases are skipped. The CI
workflow in `.github/workflows/test.yml` runs the suite, checks that the demo shell scripts parse,
checks that `channels.json` is valid JSON, and runs the citation check, which skips there because
no specification text is available to it.

### Checking citations

Comments across these repositories cite clauses of the DVB-I specification and of its
implementation guidelines. Both documents number clauses in the same ranges, so a citation naming
no document is resolved by a reader against whichever they assume. That has produced real errors:
comments citing implementation guidance for behaviour the specification governs, and clauses that
turned out to cover something else.

```bash
DVBI_SPECS=~/.local/share/dvb-i-specs tools/verify-citations.py
```

It checks that every citation names its document and that the clause exists there. Supply the two
documents yourself as plain text, outside every working tree: no specification text is carried in
these repositories. Without them the check skips. It cannot tell you whether a clause says what a
comment claims; only reading does that.

### Layout

```
scripts/dvbi-live-demo/   the live demo: channel line-up, start/stop/status, service list generator
tools/                    the citation checker
```

## Contributing

Contributions are welcome. How to raise an issue, fork the repository and open a pull request, and
the Contributor License Agreement required before code can be merged, are described at
<https://www.5g-mag.com/contributing>.

## License

Distributed under the 5G-MAG Public License v1.0. See [LICENSE](LICENSE).
