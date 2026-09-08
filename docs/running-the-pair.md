# Running the pair, end to end

The two companion applications, run from a clean checkout against public test streams. This is the
starting point; the [DVB-I live demo](../scripts/dvbi-live-demo/README.md) is the same pair fed from
your own media, encoded live on this machine.

They live in their own repositories beside this one:

- **`rt-dvb-i-application-provider`** — the DVB-I Application Provider and admin portal. It's where you build a service
  list and EPG (edit services, upload logos, publish XML).
- **`rt-dvb-i-application`** — the DVB-I Client (a.k.a. "receiver"). It's a browser player that fetches a
  service list and plays the channels in it.

The flow is: **admin publishes a service list → client consumes it and plays video.**

This tutorial walks through running both from a clean checkout to a working end-to-end demo.

## 1. Prerequisites

- Node.js (v18+ recommended) and npm
- A modern browser (Chrome/Edge/Firefox) for the client — video playback needs HLS/DASH support via `hls.js`/`dash.js`, which the client loads for you

## 2. Install dependencies

From this directory:

```bash
cd rt-dvb-i-application-provider && npm install && cd ..
cd rt-dvb-i-application && npm install && cd ..
```

## 3. Start the admin

```bash
cd rt-dvb-i-application-provider
npm start
```

You should see:

```
DVB-I Application Provider and Admin Portal  →  http://localhost:4000
Service list    →  http://localhost:4000/service-list.xml
```

Open [http://localhost:4000](http://localhost:4000) in your browser. This is the admin UI. The
project ships an example list (`config.example.json`, copied to `config.json` on first start) with
three sample services (Tears of
Steel, an Akamai UHD test stream, and an Akamai live HLS stream), so there's something to look at
immediately.

By default there is **no authentication** (`ADMIN_TOKEN` is unset) — fine for trying this out
locally, but don't leave it that way if the admin is reachable from anywhere else on the network
(see § 7).

## 4. Start the client

Open a second terminal:

```bash
cd rt-dvb-i-application
npm start
```

You should see:

```
DVB-I Client      →  http://localhost:5000
```

Open [http://localhost:5000](http://localhost:5000). The client defaults to loading
`http://localhost:4000/service-list.xml` — i.e. it's already pointed at the admin instance you just
started. You should see the same three demo channels appear, and you can click one to play it.

At this point you have a working end-to-end loop: **admin serves XML → client fetches it through its
`/proxy` endpoint (CORS-safe) → hls.js/dash.js play the stream.**

## 5. Make a change and see it flow through

To see the "end-to-end" part in action, edit something in the admin and watch it reach the client:

1. In the admin UI (`localhost:4000`), edit one of the services — e.g. change its name, logo colour,
   or add a new streaming instance — and save.
2. Refresh the client (`localhost:5000`), or use its refresh/reload control.
3. The updated service list reaches the client via `GET /service-list.xml`, which supports conditional
   `If-Modified-Since` requests, so the client only re-downloads when something actually changed.

You can also try adding a brand-new service in the admin, saving, and confirming it appears as a new
channel in the client.

The provider ships ready-made starting points. In the services toolbar, pick one from the template
selector and click **Load Template**. **Reference service (all fields, DASH)** opens the editor
pre-filled with a service in which every supported field is populated, which is both a starting
point for a new channel and a way to see what each field looks like when set. A template whose kind
is `list` replaces the whole line-up instead, after asking.

Templates live in `rt-dvb-i-application-provider/templates/` and are re-read on every use, so
adding or editing a file changes what the selector offers without restarting the server.

## 6. Point the client at a different service list (optional)

The client isn't hard-wired to the local admin — you can load any DVB-I service list URL. In the
client UI, look for the URL/settings field and paste a different `service-list.xml` URL (e.g. one
from another admin instance). It's stored in `localStorage`, so it persists across reloads.

Note: the receiver's `/proxy` endpoint is SSRF-guarded, so it rejects private, loopback and
link-local addresses and the cloud metadata IP. A service list published on this same machine is
therefore refused unless its origin is named explicitly:

```bash
PROXY_ALLOW_ORIGINS="http://localhost:4000,http://127.0.0.1:4000" npm start
```

That permits those two origins and nothing else, rather than switching the guard off. Match on
scheme, host and port: the same host on another port stays blocked.

## 7. Before exposing either app beyond your machine

Both `DEPLOYMENT.md` files (in each repo) go into detail; the essentials:

- **Admin auth**: set `ADMIN_TOKEN` before starting the admin if it will be reachable from anywhere
  but your own laptop:
  ```bash
  ADMIN_TOKEN="$(openssl rand -hex 24)" npm start
  ```
  The admin UI will prompt for the token once and remember it in `localStorage`.
- **HTTPS**: per ETSI TS 103 770 §7.3, the service list and EPG endpoints must be served over TLS
  once the admin and client aren't on the same private subnet. Either set `HTTPS_KEY_PATH` /
  `HTTPS_CERT_PATH` on both apps, or terminate TLS at a reverse proxy in front of them. Don't run
  plain HTTP outside of local dev.
- **Logging verbosity**: `LOG_LEVEL=debug|info|warn|error` on either app (default `info`).

## 8. Running the test suites

```bash
cd rt-dvb-i-application-provider && npm test   # unit tests, XSD validation, CS membership
cd rt-dvb-i-application && npm test            # unit tests, proxy guard, Playwright browser tests
```

The provider's conformance checks are opt-in and need the schema and classification scheme files,
which are deliberately not carried in these repositories. They ship with the specification, in the
electronic attachment archive that accompanies ETSI TS 103 770. Keep them outside every working
tree and point at them:

```bash
DVBI_SCHEMAS=~/.local/share/dvb-i-schemas/etsi npm test
```

Without that the two conformance checks skip cleanly and `npm test` still passes. See
`COMPLIANCE.md`.

The receiver's browser tests need a Playwright browser the first time:

```bash
cd rt-dvb-i-application && npx playwright install chromium firefox
```

`BROWSER` chooses the engine, chromium by default. Some environments cannot run chromium at all,
where a renderer cannot acquire resources and crashes; `BROWSER=firefox npm test` runs the same
suite there.

If no browser is installed the browser tests are skipped rather than failed, so `npm test` still
passes for quick iteration.

## Troubleshooting

- **Client shows no channels**: confirm the provider is running on port 4000 and that
  `http://localhost:4000/service-list.xml` loads in a browser tab directly. If it does, the
  receiver's proxy is refusing it, so check `PROXY_ALLOW_ORIGINS` above.
- **"Service list is not valid XML"**: the receiver is fetching something that is not the list,
  almost always the provider's home page rather than `/service-list.xml`. That URL is stored per
  browser, so the server looks healthy while one browser fails. Open
  `http://localhost:5000/?url=http://localhost:4000/service-list.xml` to set it.
- **Port already in use**: both apps read their port from the environment in the usual Express way;
  check nothing else on your machine is bound to 4000 or 5000.
- **Video won't play**: check the browser console — the client's CSP only allows the pinned `hls.js`
  and `dash.js` CDN versions; a mixed-content or CSP error there is the usual culprit.
