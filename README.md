<h1 align="center">DVB-I Examples</h1>
<p align="center">
  <img src="https://img.shields.io/badge/Status-Under_Development-yellow" alt="Under Development">
</p>

## Introduction

Runnable example setups for the DVB-I pair:

- **`rt-dvb-i-application-provider`** publishes a DVB-I service list (the Application Provider and
  admin portal)
- **`rt-dvb-i-application`** discovers that list and plays the channels in it (the receiver)

Each example brings the two up against real content, so the pair can be exercised end to end
without a broadcaster's service list or a public CDN.

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

## Layout

```
scripts/dvbi-live-demo/   the live demo: channel line-up, start/stop/status, service list generator
backups/                  the provider's service list as it was before an example first replaced it
```
