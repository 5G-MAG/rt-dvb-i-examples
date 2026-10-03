# DVB-I live demo, step by step

A complete DVB-I loop running on one machine, from your own media files:

**your media, encoded live on repeat → a local HTTP origin serves it as DASH → the Application
Provider publishes a service list naming those streams → the Application discovers that list and
plays the channels.**

Delivery is plain unicast HTTP from the local origin. There is no multicast, no 5G core, no
MBSF/MBSTF, no gNB or UE and no MBS client anywhere in this demo, and none of them needs to be
built to run it. Nothing leaves the machine: every service binds loopback.

These steps are the whole procedure. Following them from a cold machine reproduces the demo.

## The architecture, and how the pieces fit

DVB-I separates discovery, metadata and media. This demo runs all of it on one machine, so the
whole chain is visible:

```
  registry            "which service lists exist for CHE?"
  :7000        <───────────────────────────────────────────────┐
    │  returns the provider's service list URL                 │
    ↓                                                          │
  provider           service list: which channels exist,       │  receiver
  :4000        ───── where their media is, what is on ─────►   │  :5000
    │                content guide: schedule and now/next      │
    │                                                          │
  origin             the media itself, DASH segments ──────────┘
  :3004              rt-media-origin: your files, encoded live on repeat
```

A receiver with nothing configured asks the **registry** which lists exist. It gets back a URL,
fetches that **service list** from the provider, and shows the channels. Selecting one plays media
from the **origin**, while the provider separately answers for the content guide.

| Component | Address | Repository | Role in TS 103 770 clause 4.1 |
|---|---|---|---|
| Service List Registry | `localhost:7000` | `rt-dvb-i-service-list-registry` | Service List Registry |
| Application Provider | `localhost:4000` | `rt-dvb-i-application-provider` | Service List Server and Content Guide Server |
| Receiver | `localhost:5000` | `rt-dvb-i-application` | DVB-I client |
| Media origin | `127.0.0.1:3004` | `rt-media-origin` | MPD server |
| Live encoder, one per channel | run by the origin | `rt-media-origin` (one ffmpeg per channel) | not a DVB-I component; it produces the content |

The registry's port is 7000 rather than 6000 because 6000 is on the WHATWG blocked-ports list: a
browser refuses to fetch from it, and so does Node.

The origin is [rt-media-origin](https://github.com/5G-MAG/rt-media-origin), configured from this
demo's `channels.json`: one process that loops each channel's source file with its own ffmpeg,
packages it as live DASH and serves it. Nothing from the MBS repositories is used.

---

## 0. Prerequisites

**Software**

- Node.js 18 or newer, and npm
- ffmpeg (and ffprobe, which ships with it)
- python3, curl

**Repositories**, all checked out side by side under `~/Repos`:

```
~/Repos/DVB-I/rt-dvb-i-application-provider    the service list publisher
~/Repos/DVB-I/rt-dvb-i-application             the receiver
~/Repos/DVB-I/rt-dvb-i-service-list-registry   the service list registry
~/Repos/DVB-I/rt-dvb-i-examples                this repository
~/Repos/rt-media-origin                        the media origin and its live encoders
```

A different layout needs `REPOS_ROOT`, `DVBI_ROOT` or `MEDIA_ORIGIN_DIR` changed in `env.sh`.
Nothing else is derived independently.

`start-all.sh` installs each checkout's npm dependencies when its `node_modules` is missing. In
`rt-media-origin` it runs `npm ci`, which installs exactly what its `package-lock.json` locks and
does not rewrite that file. The radio service is served audio only, which needs an rt-media-origin
with audio-only channels (`audioOnly`, on its `development` branch at the time of writing);
`start-all.sh` stops with a message if the checkout lacks it.

**Genre classification schemes.** The registry refuses to start without `GENRE_CS_DIR`, a directory
holding `ContentCS.xml`, `FormatCS.xml` and `DVBContentSubjectCS-2019.xml` (default
`~/.local/share/dvb-i-schemas/etsi`). They are never carried in these repositories: the registry's
README says where each comes from. `start-all.sh` stops before starting anything if one is missing.

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
four checkouts if they are missing, then brings up the origin (which starts one encoder per
channel), the provider, the registry and the receiver in that order, waiting at each step until
the thing it just started actually answers.

The provider's own `config.json` and the channel logos in its `public/logos/uploaded/` are
overwritten by the demo. `start-all.sh` saves them into `run/provider-saved/` first, once, and
`stop-all.sh` puts them back, contents and modification times.

First run is the slow one: dependencies plus a cold encode. Expect a minute or so. It prints the
four URLs when everything is up.

## 2. Check it is working

```bash
./status.sh
```

A healthy run:

```
processes:
  UP   rt-dvb-i-application           pid ...
  UP   rt-dvb-i-application-provider  pid ...
  UP   rt-dvb-i-service-list-registry pid ...
  UP   rt-media-origin                pid ...

endpoints:
  media origin   listening  (HTTP 200)  http://127.0.0.1:3004/healthz
  provider       listening  (HTTP 200)  http://localhost:4000/service-list.xml
  registry       listening  (HTTP 200)  http://localhost:7000/health
  client         listening  (HTTP 200)  http://localhost:5000/health

channels:
  tv_1_live    LIVE   last published 2s ago, 72 segments
  tv_2_live    LIVE   last published 2s ago, 72 segments
  tv_3_live    LIVE   last published 2s ago, 72 segments
  radio_live   LIVE   last published 2s ago, 72 segments
```

`/healthz` on the origin lists the channel ids it was configured with.

**`LIVE` versus `UP`.** A process can be `UP` while a channel is dead: the origin stays up when one
channel's encoder stops, and the last manifest stays on disk and keeps returning 200. `LIVE` means
the manifest's `publishTime` is recent, so read the channel lines, not the process lines. Every
channel's encoder logs into `run/logs/rt-media-origin.log`, each line prefixed with the channel id
in brackets, for example `[mwc-tv-1]`.

## 3. Watch it

Open **http://localhost:5000**.

The receiver loads `http://localhost:4000/service-list.xml` by default, so the three channels
should appear on their own. Click one, or press `1`, `2`, `3` to tune by channel number.

Each channel carries a content guide, so the now/next strip and the full EPG (press `E`) have real
programmes in them rather than sitting empty. MWC TV 2 is rated 12, which the receiver's parental
controls act on if a threshold is set; the other two are unrated.

If it shows no channels, the list is not reaching it. Confirm
`http://localhost:4000/service-list.xml` loads in a browser tab, then see Troubleshooting.

## 3a. Watch it on a phone over Wi-Fi

Set `DEMO_HOST` to this machine's address on the Wi-Fi network, with the phone on the same network:

```sh
DEMO_HOST=192.168.1.202 ./start-all.sh      # use this machine's own Wi-Fi address
DEMO_HOST=192.168.1.202 ./stop-all.sh
```

The media origin then also listens on the network, and the service list, the logos, the content
guide endpoints and the registry give out that address instead of `localhost`. On the phone, use
`http://<DEMO_HOST>:4000/service-list.xml` as the service list, or `http://<DEMO_HOST>:7000/query` as the
registry, in the DVB-I Android Application ([rt-dvb-i-android-application](https://github.com/5G-MAG/rt-dvb-i-android-application)) or a browser
(`http://<DEMO_HOST>:5000/?url=http%3A%2F%2F<DEMO_HOST>%3A4000%2Fservice-list.xml`).

Plain HTTP is used, which ETSI TS 103 770 V1.2.1 clause 7.3 allows on the same private subnet:
"For the specific case that a DVB-I client connects to a DVB-I metadata endpoint located on the
same private subnet (see clause 3 of IETF RFC 1918 [27]), HTTP may be used without TLS."

The provider's editor is open to anyone on that network unless `ADMIN_TOKEN` is set: export it
before `start-all.sh` on a shared network.

## 4. Use discovery, rather than a URL you typed

The receiver loads a known URL by default, which is convenient but skips the part of DVB-I that
finds it. To exercise discovery instead:

1. Press `S` for settings
2. Set **Service List Registry** to `http://localhost:7000/query`
3. Enter a country code the demo's list is offered in: `CHE`, `DEU` or `ESP`
4. Press **Look up**

The receiver asks the registry, which answers with the lists it knows for that country, and the
receiver loads the one it is given. Asking for a country the demo's list is not offered in, `ITA`
for instance, returns an empty answer rather than an error: that is the registry filtering, not a
fault.

You can ask the registry directly too:

```bash
curl "http://localhost:7000/query?TargetCountry=CHE"
curl "http://localhost:7000/query?TargetCountry[]=CHE&TargetCountry[]=DEU"
curl "http://localhost:7000/query?Delivery=dvb-dash"
```

What it offers is `rt-dvb-i-service-list-registry/registry.json`.

## 5. See the service list itself

```bash
curl http://localhost:4000/service-list.xml
```

That is the DVB-I service list the receiver consumes: three `<Service>` entries, each with one DASH
`<ServiceInstance>` pointing at `http://127.0.0.1:3004/<stream>/manifest.mpd`.

The provider's own UI at **http://localhost:4000** shows the same list as an editable form, with an
XML preview, a Validate action and version history.

## 6. Load the demo line-up as a template

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

## 7. Change the line-up

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
| `stream` | the path the origin serves the channel under, and therefore the one the DVB-I `StreamingInstance` points at |
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
| `catchup` | a catch-up URL, emitted as an on-demand programme alongside the scheduled one, but only when a catch-up player is configured (below) |

Programme artwork uses the channel logo, so the demo carries no image files of its own.

**Catch-up needs a catch-up player.** The provider refuses to save a list in which a programme
carries a catch-up URL while no catch-up player (`catchupPlayer`, its XML AIT) is configured; see
the provider's README for the fields. A top-level `catchupPlayer` object in `channels.json` is
written into the provider's `config.json` exactly as given, and nothing in it is defaulted: the
organisation and application identifiers are the operator's own. Without one there, or already in
the provider's configuration, the generator leaves every catch-up URL out and names each on stderr,
so the list still publishes. The shipped `channels.json` has neither catch-up URLs nor a player.

Two fields are deliberately left unset on every demo channel, and the reference service template
shows them instead:

- **`subscriptionPackage`** would gate the service behind a subscription prompt the viewer has to
  clear before anything plays, which is not what a demo wants.
- **`targetRegion`** would make the provider filter the channel out of any list requested for a
  different country.

After editing:After editing:

```bash
./regen-service-list.sh        # existing channels: regenerates the list and restarts the provider
./stop-all.sh && ./start-all.sh  # added or removed a channel: the origin's configuration is regenerated
```

`regen-service-list.sh` restarts the provider deliberately: it reads `config.json` once at startup,
so rewriting that file while it runs changes nothing a receiver can see. The receiver picks the new
list up within its own 30 s poll.

## 8. Stop it

```bash
./stop-all.sh
```

It stops only what `start-all.sh` started, waits for the origin's encoders to exit with it, and
restores the provider's `config.json` and logos saved at start. A port still held afterwards is
reported, not killed: these scripts do not know what else on the machine may be using it.

---

## The scripts

| File | What it is |
|---|---|
| `env.sh` | paths, ports, encoding settings. The only file a different layout needs edited |
| `channels.json` | the channel line-up, single source of truth |
| `start-all.sh` | preflight, then origin, provider, registry, receiver |
| `status.sh` | what is running, and whether each channel is still publishing |
| `stop-all.sh` | stops what was started |
| `regen-service-list.sh` | rebuilds the list from `channels.json` and restarts the provider |
| `write-origin-config.py` | generates the rt-media-origin configuration, `run/origin/config.json` |
| `write-service-list.py` | generates the published list, and with `--emit-template` the demo template |
| `lib.sh` | logging, process, readiness and provider save/restore helpers |
| `run/` | per-run state, not tracked: logs, pidfiles, the origin's configuration and media, the saved provider files |

## What the channels actually are

Genuine live DASH, not files served as video on demand. `write-origin-config.py` gives
rt-media-origin one `live` channel per entry in `channels.json`. The origin loops each source
indefinitely (`-stream_loop -1`) and writes a rolling window, so every manifest is `type="dynamic"`
with an advancing `publishTime`, a `timeShiftBufferDepth` and a `minimumUpdatePeriod` equal to the
segment duration. A receiver joining at any moment joins at the live edge, and the channel never
ends.

Each channel is one 960x540 H.264 (Main) rendition with AAC audio at 64 kbit/s, the encoding the
demo used before it moved to rt-media-origin. In `env.sh`:

| Setting | Default | What it does |
|---|---|---|
| `LIVE_SEG_DURATION` | `4` | segment duration in seconds, and therefore the manifest update period: shorter joins closer to the live edge and costs more requests |
| `LIVE_WINDOW`, `LIVE_EXTRA_WINDOW` | `24`, `48` | segments the manifest lists, and segments kept on disk beyond those; the origin deletes anything older |
| `LIVE_VIDEO_BITRATE` | `400k` | video bit rate |

**Radio.** A `radio` channel is served as an rt-media-origin audio-only channel (`audioOnly: true`):
the origin takes the source's audio and encodes no video, so the MPD has a single audio
AdaptationSet whatever the source file carries. A `linear` channel keeps its video ladder.

The origin also serves its own dashboard at `http://127.0.0.1:3004/dashboard/`, which shows each
channel's encoder and can stop and start it.

## Tests

The generator has its own tests, standard library only:

```bash
cd ~/Repos/DVB-I/rt-dvb-i-examples/scripts/dvbi-live-demo
python3 -m unittest -v test_generator
```

Every case corresponds to something that has actually gone wrong, so a failure is a defect that
reached a running receiver once already. They cover the two version rules (a changed service moves
forward from what was published rather than resetting, and `ServiceList@version` bumps on a real
change but not on a no-op republish, which is what tells a receiver to re-read the list at all),
the shape of the generated service, and the schema constraints that have bitten: a `@CGSID` that
must be an NCName, and a `logoUrl` that must stay relative.

The origin configuration has its own cases, which pin what the demo needs from rt-media-origin
rather than recording past defects: each channel served at the path the service list names,
looping its source from `CONTENT_ROOT`, the window settings taken from `env.sh`, radio served audio only and
television with its video ladder. One, `TestOriginConfigAgainstSchema`, runs the configuration generated from
the shipped `channels.json` through rt-media-origin's own validator, and is skipped when that
checkout or its dependencies are not there.

Another, `TestTemplateDrift`, regenerates the list template from `channels.json` and compares
it with the copy in the provider's `templates/`. Regenerating that template is a manual step, so
this is what notices when it starts describing a line-up that no longer exists. If it fails:

```bash
source ./env.sh && ./write-service-list.py --emit-template
```

## Conformance

The published list and the demo template are both validated against the real DVB-I and TV-Anytime
schemas by the provider's own conformance test:

```bash
cd ~/Repos/DVB-I/rt-dvb-i-application-provider
DVBI_SCHEMAS=~/.local/share/dvb-i-schemas/etsi npm test
```

That runs three checks: unit tests, XSD validation, and classification scheme membership. The last
one matters because CS references are typed `anyURI`, so a schema-valid list can still name a term
that does not exist; it checks each emitted term against the scheme files, which ship in the same
archive as the schemas.

That test is bring-your-own-schema and skips cleanly without one, so no schema file is ever carried
in these repositories. The authoritative copies ship with the specification itself, in the
electronic attachment archive that accompanies ETSI TS 103 770 (annex B lists its contents); keep
them somewhere outside every working tree, as above. With them present the test validates the
sample list, the live `config.json`, every file in `templates/`, and both EPG endpoints, and prints
which schema files it used.

The generator targets **ETSI TS 103 770 V1.2.1 (2024-09)**, which is the issue matching the
namespaces it emits (`urn:dvb:metadata:servicediscovery:2024`, `urn:dvb:metadata:servicediscovery-types:2023`,
`urn:tva:metadata:2024`). See the provider's `COMPLIANCE.md` for what is and is not covered.

## Troubleshooting

**The receiver shows no channels.** Check `http://localhost:4000/service-list.xml` loads directly.
If it does, the receiver's `/proxy` is refusing it: that endpoint has an SSRF guard that rejects
loopback addresses, which is exactly where the provider sits here. `start-all.sh` therefore starts
the receiver with `PROXY_ALLOW_ORIGINS` naming the provider's and the registry's origins (see
`env.sh`), and nothing else. Confirm with `grep PROXY_ALLOW run/logs/rt-dvb-i-application.log`
or the warning listing those origins at the top of that log. `ALLOW_LOOPBACK_PROXY` is no longer
read by the receiver and is not set.

**"Not over TLS" warnings.** The provider, registry and receiver all run without certificates here,
so each logs, and the receiver also shows, a warning that ETSI TS 103 770 V1.2.1 clause 7.3
requires HTTP over TLS, with one exception: "For the specific case that a DVB-I client connects to
a DVB-I metadata endpoint located on the same private subnet (see clause 3 of IETF RFC 1918 [27]),
HTTP may be used without TLS." Loopback is not such a subnet. The warning is expected in this demo
and does not stop anything from loading. `start-all.sh` also passes the provider
`PLAIN_HTTP=private-subnet` (`ADMIN_PLAIN_HTTP` in `env.sh`): an earlier provider refused to serve
plain HTTP without it, and the current one reads it as the default.

**"Service list is not valid XML".** The receiver is fetching something that is not the list,
almost always the provider's home page (`http://localhost:4000/`) rather than the list itself
(`http://localhost:4000/service-list.xml`). That URL lives in the browser's own storage, so the
server looks perfectly healthy while one browser fails. Fix it by opening the receiver with the URL
in the query string, which sets and remembers it:

```
http://localhost:5000/?url=http://localhost:4000/service-list.xml
```

or clear the stored value from the browser console and reload:

```js
localStorage.removeItem('dvbi-url'); location.reload();
```

**Channels listed but no picture.** Look at the browser console. Segments are fetched straight from
the origin rather than through the receiver's proxy; the origin sends
`Access-Control-Allow-Origin: *` (`cors` in its generated configuration) and the receiver's CSP
allows `http:` media, so a failure here is usually the encoder. Run `./status.sh` and look for a
`STALE` channel, then at that channel's lines in `run/logs/rt-media-origin.log`.

**A rename in the provider does not reach the receiver.** `ServiceName` in the published list is
built from the *Multi-language Service Names* entries whenever a service has any, not from the
Service Name field, so an entry still holding the old text overrides the rename and the receiver
keeps showing the old name. Either clear those entries or update them too. In `channels.json`, a
language entry given only a `lang` reuses the channel's `name`, which avoids the problem entirely.

**The receiver's browser tests fail but nothing else does.** Chromium cannot run in some
environments: every subresource fetch fails with `net::ERR_INSUFFICIENT_RESOURCES` and the renderer
crashes, so the page loads and nothing renders. Run the suite on another engine instead, which is
already installed with Playwright:

```bash
cd ~/Repos/DVB-I/rt-dvb-i-application && BROWSER=firefox npm test
```

**Port already bound.** Ports are set in `env.sh`. `./stop-all.sh` reports a foreign process holding
one rather than killing it. Port 3004 is also the origin port of the MBS demo in rt-mbs-examples;
with that demo up, move this one's origin: `MEDIA_PORT=3014 ./start-all.sh`, and pass the same
`MEDIA_PORT` to `status.sh` and `stop-all.sh`. The service list follows it.

**A channel is missing after editing `channels.json`.** `regen-service-list.sh` only republishes the
list; a new channel also needs its encoder, so use `./stop-all.sh && ./start-all.sh`.

**The provider's "Test URL" button rejects these URLs.** That button applies its own
private-address guard, separate from playback. Playback is unaffected.

## Limitations

- Loopback only, by design. Reaching the demo from another device means changing the addresses in
  `env.sh` and re-examining both SSRF guards, neither of which this demo does.
- One encoder per channel, each a full transcode. Three 1080p sources at once is a real CPU load;
  reduce the line-up on a modest machine.
