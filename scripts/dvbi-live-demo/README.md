# DVB-I live demo, step by step

A complete DVB-I loop running on one machine, from your own media files:

**your media, encoded live on repeat → a local HTTP origin serves it as DASH → the Application
Provider publishes a service list naming those streams → the Application discovers that list and
plays the channels.**

Delivery is plain unicast HTTP from the local origin. There is no multicast, no 5G core, no
MBSF/MBSTF, no gNB or UE and no MBS client anywhere in this demo, and none of them needs to be
built to run it. Nothing leaves the machine: every service binds loopback.

These steps are the whole procedure. Following them from a cold machine reproduces the demo.

## What runs

| Component | Address | Comes from |
|---|---|---|
| Media origin | `127.0.0.1:3004` | `rt-mbs-examples/express-mock-media-server` |
| Live encoder, one per channel | writes into that origin | `rt-mbs-examples/scripts/mbs-broadcast-demo/live-encoder.sh` |
| DVB-I Application Provider | `localhost:4000` | `rt-dvb-i-application-provider` |
| DVB-I Application (the receiver) | `localhost:5000` | `rt-dvb-i-application` |

Only the server side of the MBS broadcast demo is borrowed: the origin and the encoder. That is
the one dependency this demo has on the MBS repositories.

---

## 0. Prerequisites

**Software**

- Node.js 18 or newer, and npm
- ffmpeg
- python3, curl

**Repositories**, all checked out side by side under `~/Repos`:

```
~/Repos/DVB-I/rt-dvb-i-application-provider    the service list publisher
~/Repos/DVB-I/rt-dvb-i-application             the receiver
~/Repos/DVB-I/rt-dvb-i-examples                this repository
~/Repos/rt-mbs/rt-mbs-examples                 for the media origin and the live encoder
```

A different layout needs `REPOS_ROOT`, `DVBI_ROOT` or `MBS_EXAMPLES_ROOT` changed in `env.sh`.
Nothing else is derived independently.

**Content.** Your own media, in whatever directory `CONTENT_ROOT` in `env.sh` points at
(default `~/MWC_TV_RADIO`). The shipped line-up expects:

| File | Becomes |
|---|---|
| `TV_1.mp4` | MWC TV 1 |
| `TV_2.mp4` | MWC TV 2 |
| `RADIO.mp4` | MWC Radio |
| `TV_1.png`, `TV_2.png`, `RADIO.png` | the channel logos (optional) |

Any H.264/AAC MP4 works. To use different files, edit `channels.json` (section 6). Media is read
only, never written to, and is deliberately not carried in this repository.

## 1. Start it

```bash
cd ~/Repos/DVB-I/rt-dvb-i-examples/scripts/dvbi-live-demo
./start-all.sh
```

The script checks every prerequisite before starting anything, installs npm dependencies in the
three checkouts if they are missing, then brings up the origin, the encoders, the provider and the
receiver in that order, waiting at each step until the thing it just started actually answers.

First run is the slow one: dependencies plus a cold encode. Expect a minute or so. It prints the
four URLs when everything is up.

## 2. Check it is working

```bash
./status.sh
```

A healthy run:

```
processes:
  UP   encoder-mwc-radio              pid ...
  UP   encoder-mwc-tv-1               pid ...
  UP   encoder-mwc-tv-2               pid ...
  UP   media-server                   pid ...
  UP   rt-dvb-i-application           pid ...
  UP   rt-dvb-i-application-provider  pid ...

endpoints:
  media origin   listening  (HTTP 404)  http://127.0.0.1:3004/
  admin          listening  (HTTP 200)  http://localhost:4000/service-list.xml
  client         listening  (HTTP 200)  http://localhost:5000/health

channels:
  tv_1_live    LIVE   last published 2s ago, 30 segments
  tv_2_live    LIVE   last published 2s ago, 30 segments
  radio_live   LIVE   last published 3s ago, 30 segments
```

Two things to read carefully:

- **`HTTP 404` on the media origin is correct.** It serves static files with directory listing off,
  so its root has nothing to return. `listening` is the health signal, not the status code.
- **`LIVE` versus `UP`.** A process can be `UP` while its channel is dead: the last manifest stays
  on disk and keeps returning 200 after an encoder stops. `LIVE` means the manifest's `publishTime`
  is recent, so read the channel lines, not the process lines. A `STALE` channel's log is in
  `run/logs/encoder-<id>.log`.

## 3. Watch it

Open **http://localhost:5000**.

The receiver loads `http://localhost:4000/service-list.xml` by default, so the three channels
should appear on their own. Click one, or press `1`, `2`, `3` to tune by channel number.

Each channel carries a content guide, so the now/next strip and the full EPG (press `E`) have real
programmes in them rather than sitting empty. MWC TV 2 is rated 12, which the receiver's parental
controls act on if a threshold is set; the other two are unrated.

If it shows no channels, the list is not reaching it. Confirm
`http://localhost:4000/service-list.xml` loads in a browser tab, then see Troubleshooting.

## 4. See the service list itself

```bash
curl http://localhost:4000/service-list.xml
```

That is the DVB-I service list the receiver consumes: three `<Service>` entries, each with one DASH
`<ServiceInstance>` pointing at `http://127.0.0.1:3004/<stream>/manifest.mpd`.

The provider's own UI at **http://localhost:4000** shows the same list as an editable form, with an
XML preview, a Validate action and version history.

## 5. Load the demo line-up as a template

The provider ships this demo's channels as a loadable template, so the exact line-up can be
restored, or dropped into another provider instance, without running the generator:

1. Open **http://localhost:4000**
2. In the services toolbar, pick **DVB-I live demo channels (local origin, DASH)** from the
   template selector
3. Click **Load Template**, confirm the replacement
4. Click **Save & Publish**

The template is `rt-dvb-i-application-provider/templates/dvbi-local-live-demo.json`, generated from
this demo's own `channels.json` by the same code that writes the published list, so the two cannot
drift apart. Regenerate it after changing the line-up:

```bash
source ./env.sh && ./write-service-list.py --emit-template
```

The other template in that selector, **Reference service (all fields, DASH)**, is a single service
with every supported field populated. It opens the editor pre-filled rather than replacing the
list, so it works as a starting point for a new channel and as a reference for what each field
looks like when set.

Its stream URLs point at loopback, so they only resolve while this demo is running.

## 6. Change the line-up

`channels.json` is the single definition of what is broadcast. The encoders, the published service
list and the loadable template are all generated from it, so they cannot disagree.

```json
{
  "id": "mwc-tv-1",
  "name": "MWC TV 1",
  "lcn": 1,
  "type": "linear",
  "genre": "entertainment",
  "parentalRating": 0,
  "source": "TV_1.mp4",
  "stream": "tv_1_live",
  "logo": "TV_1.png",
  "logoBg": "#0a6ebd",
  "letters": "TV1",
  "languages": [{ "lang": "fr", "name": "MWC TV 1" }],
  "audioDescription": true,
  "hardOfHearing": true,
  "subtitleLanguage": "en",
  "programmes": [
    {
      "title": "Media over 5G",
      "dur": 30,
      "desc": "How broadcast and broadband delivery meet in a single 5G network.",
      "genre": "documentary",
      "parentalAge": 0,
      "series": { "title": "Media over 5G", "number": 1, "episode": 1 }
    }
  ]
}
```

| Field | What it does |
|---|---|
| `source`, `logo` | filenames under `CONTENT_ROOT` |
| `stream` | the directory the encoder writes, and the path the DVB-I `StreamingInstance` points at |
| `type` | `linear` for TV, `radio` for linear radio (emitted as the `linear-radio` service type) |
| `genre`, `parentalRating` | service-level classification and minimum age |
| `languages` | extra service name translations; English is taken from `name` automatically |
| `audioDescription`, `hardOfHearing`, `subtitleLanguage` | accessibility signalling on the instance |
| `letters`, `logoBg` | fallback the provider uses to draw a lettered logo when a channel has no logo file |
| `programmes` | the content guide, see below |

### The content guide

Each `programmes` entry becomes a TV-Anytime programme served from the provider's own
`/epg/schedule` and `/epg/nownext` endpoints, which the service list advertises as its
`ContentGuideSource`. The provider **loops** a channel's programmes to fill the schedule window, so
these describe a repeating day rather than a dated one: the durations decide the shape of the guide,
not any wall-clock time.

| Field | Notes |
|---|---|
| `title`, `dur`, `desc` | `dur` is minutes and is the only one that is required alongside the title |
| `genre` | falls back to the channel's own genre when absent |
| `parentalAge` | minimum age for the programme, separate from the service-level rating |
| `series` | `{title, number, episode}`, emitted as a series group with `MemberOf` so episodes are linked |
| `catchup` | a catch-up URL, emitted as an on-demand programme alongside the scheduled one |

Programme artwork uses the channel logo, so the demo carries no image files of its own.

Two fields are deliberately left unset on every demo channel, and the reference service template
shows them instead:

- **`subscriptionPackage`** would gate the service behind a subscription prompt the viewer has to
  clear before anything plays, which is not what a demo wants.
- **`targetRegion`** would make the provider filter the channel out of any list requested for a
  different country.

After editing:After editing:

```bash
./regen-service-list.sh        # existing channels: regenerates the list and restarts the provider
./stop-all.sh && ./start-all.sh  # added or removed a channel: an encoder has to start or stop
```

`regen-service-list.sh` restarts the provider deliberately: it reads `config.json` once at startup,
so rewriting that file while it runs changes nothing a receiver can see. The receiver picks the new
list up within its own 30 s poll.

## 7. Stop it

```bash
./stop-all.sh
```

It stops only what `start-all.sh` started. A port still held afterwards is reported, not killed:
these scripts do not know what else on the machine may be using it.

---

## The scripts

| File | What it is |
|---|---|
| `env.sh` | paths, ports, encoding settings. The only file a different layout needs edited |
| `channels.json` | the channel line-up, single source of truth |
| `start-all.sh` | preflight, then origin, encoders, provider, receiver |
| `status.sh` | what is running, and whether each channel is still publishing |
| `stop-all.sh` | stops what was started |
| `regen-service-list.sh` | rebuilds the list from `channels.json` and restarts the provider |
| `write-service-list.py` | generates the published list, and with `--emit-template` the demo template |
| `lib.sh` | logging, process and readiness helpers |
| `run/logs/`, `run/pids/` | per-run state, not tracked |

## What the channels actually are

Genuine live DASH, not files served as video on demand. Each encoder loops its source
indefinitely (`-stream_loop -1`) and writes a rolling window, so every manifest is `type="dynamic"`
with an advancing `publishTime`, a `timeShiftBufferDepth` and a `minimumUpdatePeriod` equal to the
segment duration. A receiver joining at any moment joins at the live edge, and the channel never
ends.

`LIVE_SEG_DURATION` in `env.sh` sets the segment duration and therefore the manifest update period:
shorter joins closer to the live edge and costs more requests.

## Conformance

The published list and the demo template are both validated against the real DVB-I and TV-Anytime
schemas by the provider's own conformance test:

```bash
cd ~/Repos/DVB-I/rt-dvb-i-application-provider && npm run test:xsd
```

That test is bring-your-own-schema: it skips cleanly unless you have placed the schema closure in
its gitignored `test/schemas/` directory. See the header of `test/xsd-validate.js` for the file
list. With the schemas present it validates the sample list, the live `config.json`, every file in
`templates/`, and both EPG endpoints.

The generator targets **ETSI TS 103 770 V1.2.1 (2024-09)**, which is the issue matching the
namespaces it emits (`urn:dvb:metadata:servicediscovery:2024`, `urn:dvb:metadata:servicediscovery-types:2023`,
`urn:tva:metadata:2024`). See the provider's `COMPLIANCE.md` for what is and is not covered.

## Troubleshooting

**The receiver shows no channels.** Check `http://localhost:4000/service-list.xml` loads directly.
If it does, the receiver's `/proxy` is refusing it: that endpoint has an SSRF guard that rejects
loopback addresses, which is exactly where the provider sits here. `start-all.sh` therefore starts
the receiver with `ALLOW_LOOPBACK_PROXY=1`, the escape hatch its own source documents for local
testing. Confirm with `grep ALLOW_LOOPBACK run/logs/rt-dvb-i-application.log`, which shows the
warning it prints when the flag is on. Never set that flag on a deployment reachable from untrusted
networks: it disables the guard outright.

**Channels listed but no picture.** Look at the browser console. Segments are fetched straight from
the origin rather than through the receiver's proxy; the origin sends
`Access-Control-Allow-Origin: *` and the receiver's CSP allows `http:` media, so a failure here is
usually the encoder. Run `./status.sh` and look for a `STALE` channel.

**A rename in the provider does not reach the receiver.** `ServiceName` in the published list is
built from the *Multi-language Service Names* entries whenever a service has any, not from the
Service Name field, so an entry still holding the old text overrides the rename and the receiver
keeps showing the old name. Either clear those entries or update them too. In `channels.json`, a
language entry given only a `lang` reuses the channel's `name`, which avoids the problem entirely.

**Port already bound.** Ports are set in `env.sh`. `./stop-all.sh` reports a foreign process holding
one rather than killing it.

**A channel is missing after editing `channels.json`.** `regen-service-list.sh` only republishes the
list; a new channel also needs its encoder, so use `./stop-all.sh && ./start-all.sh`.

**The provider's "Test URL" button rejects these URLs.** That button applies its own
private-address guard, separate from playback. Playback is unaffected.

## Limitations

- Loopback only, by design. Reaching the demo from another device means changing the addresses in
  `env.sh` and re-examining both SSRF guards, neither of which this demo does.
- One encoder per channel, each a full transcode. Three 1080p sources at once is a real CPU load;
  reduce the line-up on a modest machine.
