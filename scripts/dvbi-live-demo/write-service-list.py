#!/usr/bin/env python3
"""Generate the DVB-I admin's service list from channels.json.

The admin reads its line-up from its own config.json, whose path is fixed in
rt-dvb-i-application-provider/server.js, so this writes that file rather than pointing the admin elsewhere.
Everything outside the services list (the admin's own settings) is preserved; only the
list identity and the services themselves are replaced. Re-running is safe: the list is
rebuilt from channels.json each time rather than appended to.

Usage:
  write-service-list.py               write the admin's config.json
  write-service-list.py --dry-run     print the services it would write, change nothing
  write-service-list.py --emit-template
                                      write the demo as a loadable list template into the
                                      admin's templates/ directory instead of publishing it

The template is built by the same function that builds the published list, so a template
loaded in the admin cannot drift from what the demo actually broadcasts.

Catch-up: the provider refuses to save a list in which a programme carries a catch-up URL while no
catch-up player (catchupPlayer in its config.json) is configured, because the on-demand programme
it implies needs that player's XML AIT. A top-level "catchupPlayer" object in channels.json is
written into config.json as given; none of its values is defaulted here. Without one, in
channels.json or already in config.json, every programme's catch-up URL is left out and named on
stderr, so the list still publishes.

Reads CHANNELS_FILE, ADMIN_DIR, MEDIA_ORIGIN and ADMIN_ORIGIN from the environment (env.sh).
"""
import json, os, sys

DRY_RUN       = "--dry-run" in sys.argv
EMIT_TEMPLATE = "--emit-template" in sys.argv

CHANNELS_FILE = os.environ["CHANNELS_FILE"]
ADMIN_DIR     = os.environ["ADMIN_DIR"]
MEDIA_ORIGIN  = os.environ["MEDIA_ORIGIN"]
ADMIN_ORIGIN  = os.environ["ADMIN_ORIGIN"]
CONFIG        = os.path.join(ADMIN_DIR, "config.json")
CONFIG_EXAMPLE = os.path.join(ADMIN_DIR, "config.example.json")


def languages(c):
    """Service name translations. English comes from the channel's own name rather than being
    repeated in channels.json, so the two cannot disagree."""
    out = [{"lang": "en", "name": c["name"]}]
    for extra in c.get("languages", []):
        if extra.get("lang") != "en":
            out.append({"lang": extra["lang"], "name": extra.get("name", c["name"])})
    return out


def programme(c, p, catchup=True):
    """One content guide entry. The provider loops a service's programmes to fill its schedule
    window, so these describe a repeating day rather than a dated one. catchup=False leaves out
    the catch-up URL: see the module docstring."""
    series = p.get("series") or {}
    return {
        "title": p["title"],
        "dur": p["dur"],
        "desc": p.get("desc", ""),
        "genre": p.get("genre") or c.get("genre") or None,
        "parentalAge": p.get("parentalAge"),
        # Programme images are emitted into the content guide verbatim, with no base URL applied,
        # so they have to be absolute. The channel logo stands in for per-programme artwork, which
        # keeps the demo free of image files it would otherwise have to carry.
        "image": f"{ADMIN_ORIGIN}/logos/uploaded/{c['id']}.png" if c.get("logo") else None,
        "seriesTitle": series.get("title"),
        "seriesNumber": series.get("number"),
        "episodeNumber": series.get("episode"),
        "catchupUrl": p.get("catchup") if catchup else None,
    }


def service(c, catchup=True):
    """One DVB-I service, with a single DASH StreamingInstance pointing at the live
    presentation rt-media-origin serves for this channel."""
    return {
        "id": c["id"],
        "uid": f"tag:5g-mag.org,2026:service:{c['id']}",
        "version": 1,
        "enabled": True,
        "name": c["name"],
        "provider": "5G-MAG",
        "lcn": c["lcn"],
        "type": c.get("type", "linear"),
        "genre": c.get("genre", ""),
        "parentalRating": c.get("parentalRating"),
        "logoLetters": c.get("letters", "TV"),
        "logoBg": c.get("logoBg", "#2c3e50"),
        # Points at the file install_logos() (start-all.sh) copies into the provider's own
        # public/logos/uploaded/. The provider's /logos/<id> route generates a lettered SVG
        # instead whenever a service carries no logoUrl, so a channel with no logo file
        # still renders.
        #
        # Kept as a path on the provider rather than an absolute URL, so the list stays correct if
        # it is served on another port or host: the generator resolves a relative logoUrl against
        # whatever base it is answering on.
        "logoUrl": f"/logos/uploaded/{c['id']}.png" if c.get("logo") else "",
        "languages": languages(c),
        # No target region: the demo's channels are not region-restricted, and setting one makes
        # the provider filter them out of any list requested for a different country.
        "targetRegion": "",
        # No subscription package: a service carrying one is gated in the receiver behind a
        # subscription prompt, which a demo should not require anyone to clear.
        "subscriptionPackage": "",
        # No per-service guide override: these services use the list-level ContentGuideSource,
        # which is this same provider's own /epg endpoints.
        "customEpgUrl": "",
        "availableFrom": None,
        "availableTo": None,
        "linkedApp": None,
        "instances": [{
            "id": f"inst-{c['id']}-dash",
            "label": f"{c['name']} (live DASH)",
            "priority": 1,
            "hasAudioDescription": bool(c.get("audioDescription")),
            "hasHardOfHearing": bool(c.get("hardOfHearing")),
            # SubtitleCarriageCS:2023 term 3, subtitles carried in the ISOBMFF/DASH presentation,
            # which is where they would be for this delivery.
            "subtitleCarriage": 3,
            "subtitleLanguage": c.get("subtitleLanguage", "en"),
            "drmSystems": [],
            "url": f"{MEDIA_ORIGIN}/{c['stream']}/manifest.mpd",
            "type": "dash",
        }],
        "epgPrograms": [programme(c, p, catchup) for p in c.get("programmes", [])],
    }


LIST_NAME = os.environ.get("LIST_NAME", "5G-MAG")
EPG_ID    = "local-live-demo-epg"

TEMPLATE_NOTE = [
    "The DVB-I live demo's own channel line-up, as a loadable list template.",
    "",
    "Generated by rt-dvb-i-examples/scripts/dvbi-live-demo/write-service-list.py --emit-template",
    "from that demo's channels.json, by the same code that writes the published list, so this",
    "template and what the demo broadcasts cannot drift apart. Regenerate it after editing",
    "channels.json rather than editing this file.",
    "",
    "The stream URLs point at the demo's own media origin on loopback, so they only resolve while",
    "that demo is running. Loading this template replaces the services in the current list.",
]


def list_template(cfg_services):
    return {
        "_comment": TEMPLATE_NOTE,
        "name": "DVB-I live demo channels (local origin, DASH)",
        "kind": "list",
        "list": {
            "listName": LIST_NAME,
            "providerName": "5G-MAG",
            "listLang": "en",
            "epg": {"id": EPG_ID, "providerName": "5G-MAG"},
            "services": cfg_services,
        },
    }


def reconcile_versions(services, existing):
    """Carry each service's version forward, incrementing it only when the service actually
    changed.

    Service@version is how a receiver notices that a service's metadata has been revised, so
    regenerating must never send it backwards: a service edited in the provider (which bumps the
    version on save) would otherwise be republished as version 1 and look older than the copy a
    receiver already holds.
    """
    by_id = {s.get("id"): s for s in existing}
    for svc in services:
        prev = by_id.get(svc["id"])
        if not prev:
            svc["version"] = 1
            continue
        old_version = prev.get("version", 1)
        # Compare everything except the version itself: an unchanged service keeps its version,
        # so republishing an untouched list does not churn versions for receivers.
        a = {k: v for k, v in prev.items() if k != "version"}
        b = {k: v for k, v in svc.items() if k != "version"}
        svc["version"] = old_version if a == b else old_version + 1
    return services


def report_dropped_catchup(channels):
    for c in channels:
        for p in c.get("programmes", []):
            if p.get("catchup"):
                print(f"  {c['id']}: catch-up URL of \"{p['title']}\" left out, no catchupPlayer is configured",
                      file=sys.stderr)


def main():
    with open(CHANNELS_FILE) as f:
        doc = json.load(f)
    channels = doc["channels"]
    player = doc.get("catchupPlayer")

    # Same DEMO_CHANNELS filter the origin configuration honours (write-origin-config.py, and
    # lib.sh's channel_lines). Applied here too so the published list never offers a service that
    # nothing is encoding.
    only = [x for x in os.environ.get("DEMO_CHANNELS", "").replace(",", " ").split() if x]
    if only:
        channels = [c for c in channels if c["id"] in only]

    if EMIT_TEMPLATE:
        services = [service(c, catchup=player is not None) for c in channels]
        if player is None:
            report_dropped_catchup(channels)
        out = os.path.join(ADMIN_DIR, "templates", "dvbi-local-live-demo.json")
        os.makedirs(os.path.dirname(out), exist_ok=True)
        with open(out, "w") as f:
            json.dump(list_template(services), f, indent=2)
            f.write("\n")
        print(f"  wrote {out}")
        for s in services:
            print(f"  LCN {s['lcn']}  {s['name']:<12} {s['instances'][0]['url']}")
        return

    # A fresh provider clone has no config.json until its server first starts; the provider then
    # copies config.example.json, so the generator starts from the same file.
    with open(CONFIG if os.path.exists(CONFIG) else CONFIG_EXAMPLE) as f:
        cfg = json.load(f)
    has_player = player is not None or cfg.get("catchupPlayer") is not None
    services = [service(c, catchup=has_player) for c in channels]
    if not has_player:
        report_dropped_catchup(channels)
    reconcile_versions(services, cfg.get("services", []))
    new_values = {
        "listName": LIST_NAME,
        "providerName": "5G-MAG",
        "listLang": "en",
        # CGSID is typed xs:ID by the DVB-I schema (ContentGuideProviderIdType), so it must be an
        # NCName: a leading digit is not allowed, which ruled out the obvious "5g-mag-..." spelling.
        "epg": {"id": EPG_ID, "providerName": "5G-MAG"},
        "services": services,
    }
    if player is not None:
        new_values["catchupPlayer"] = player
    # ServiceList@version is what tells a running receiver the list has been revised: it re-reads
    # the list only when that number changes, so anything republished under an unchanged version is
    # ignored by every receiver already showing the list. Bump it whenever the generated list
    # actually differs, and leave it alone when it does not, so republishing an untouched list does
    # not make every receiver reload for nothing.
    changed = any(cfg.get(k) != v for k, v in new_values.items())
    cfg.update(new_values)
    if changed:
        try:
            cfg["version"] = int(cfg.get("version", 0)) + 1
        except (TypeError, ValueError):
            cfg["version"] = 1

    if DRY_RUN:
        print(json.dumps(cfg["services"], indent=2))
        return
    with open(CONFIG, "w") as f:
        json.dump(cfg, f, indent=2)
    for s in cfg["services"]:
        print(f"  LCN {s['lcn']}  {s['name']:<12} {s['instances'][0]['url']}")


if __name__ == "__main__":
    main()
