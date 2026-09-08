#!/usr/bin/env python3
"""Tests for write-service-list.py.

Run from this directory:  python3 -m unittest -v test_generator

No dependencies beyond the standard library. Every case here corresponds to something that
has actually gone wrong, so a failure means a defect that reached a running receiver once
already, not a hypothetical.

The generator reads its configuration from the environment at import time, so each test
imports it fresh against a temporary provider directory. Nothing here writes to the real
provider or to the published list.
"""
import copy
import importlib.util
import json
import os
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
GENERATOR = HERE / "write-service-list.py"
CHANNELS = HERE / "channels.json"

MINIMAL_CONFIG = {
    "version": 1,
    "listName": "unset",
    "providerName": "unset",
    "listLang": "en",
    "listId": "",
    "targetCountry": "",
    "epg": {"id": "unset", "providerName": "unset"},
    "services": [],
}

ONE_CHANNEL = {
    "channels": [
        {
            "id": "demo-one",
            "name": "Demo One",
            "lcn": 1,
            "type": "linear",
            "genre": "entertainment",
            "parentalRating": 0,
            "source": "ONE.mp4",
            "stream": "one_live",
            "logo": "ONE.png",
            "logoBg": "#123456",
            "letters": "ON1",
            "languages": [{"lang": "fr"}, {"lang": "de", "name": "Demo Eins"}],
            "audioDescription": True,
            "hardOfHearing": True,
            "subtitleLanguage": "en",
            "programmes": [
                {"title": "Opener", "dur": 30, "desc": "First.", "parentalAge": 0},
                {
                    "title": "Episode",
                    "dur": 45,
                    "desc": "Second.",
                    "genre": "drama",
                    "parentalAge": 12,
                    "series": {"title": "A Series", "number": 2, "episode": 4},
                    "catchup": "https://example.com/catchup/1",
                },
            ],
        }
    ]
}


def load_generator(admin_dir, channels_file, media_origin="http://127.0.0.1:3004",
                   admin_origin="http://localhost:4000"):
    """Import the generator against a throwaway provider directory."""
    os.environ.update({
        "CHANNELS_FILE": str(channels_file),
        "ADMIN_DIR": str(admin_dir),
        "MEDIA_ORIGIN": media_origin,
        "ADMIN_ORIGIN": admin_origin,
    })
    spec = importlib.util.spec_from_file_location("dvbi_generator", GENERATOR)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    mod.DRY_RUN = False
    mod.EMIT_TEMPLATE = False
    return mod


class GeneratorTestCase(unittest.TestCase):
    """Base class giving each test its own provider directory and channel file."""

    channels = ONE_CHANNEL

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.admin = Path(self.tmp.name)
        (self.admin / "templates").mkdir()
        self.config_path = self.admin / "config.json"
        self.config_path.write_text(json.dumps(MINIMAL_CONFIG))
        self.channels_path = self.admin / "channels.json"
        self.channels_path.write_text(json.dumps(self.channels))
        self.gen = load_generator(self.admin, self.channels_path)
        self.addCleanup(self.tmp.cleanup)

    def run_generator(self):
        """Write the list, and return what landed in config.json."""
        stdout = sys.stdout
        sys.stdout = open(os.devnull, "w")
        try:
            self.gen.main()
        finally:
            sys.stdout.close()
            sys.stdout = stdout
        return json.loads(self.config_path.read_text())

    def set_config(self, cfg):
        self.config_path.write_text(json.dumps(cfg))


class TestVersions(GeneratorTestCase):
    """Version handling. Both of these shipped broken once: a service version that went
    backwards, and a list version that never moved, which is what tells a running receiver
    the list has been revised at all."""

    def test_new_service_starts_at_version_one(self):
        self.assertEqual(self.run_generator()["services"][0]["version"], 1)

    def test_unchanged_service_keeps_its_version(self):
        first = self.run_generator()
        first["services"][0]["version"] = 7
        self.set_config(first)
        again = self.run_generator()
        self.assertEqual(again["services"][0]["version"], 7,
                         "republishing an unchanged service must not churn its version")

    def test_changed_service_increments_from_the_published_version(self):
        first = self.run_generator()
        first["services"][0]["version"] = 7
        first["services"][0]["name"] = "Something Else"
        self.set_config(first)
        again = self.run_generator()
        self.assertEqual(again["services"][0]["version"], 8,
                         "a changed service must move forward from what was published, never back to 1")

    def test_list_version_bumps_when_the_list_changes(self):
        before = json.loads(self.config_path.read_text())["version"]
        after = self.run_generator()["version"]
        self.assertEqual(after, before + 1)

    def test_list_version_held_when_nothing_changes(self):
        first = self.run_generator()["version"]
        second = self.run_generator()["version"]
        self.assertEqual(first, second,
                         "an unchanged list must not bump its version, or every receiver reloads for nothing")


class TestServiceFields(GeneratorTestCase):

    def test_logo_url_is_a_path_not_an_absolute_url(self):
        svc = self.run_generator()["services"][0]
        self.assertEqual(svc["logoUrl"], "/logos/uploaded/demo-one.png")
        self.assertFalse(re.match(r"^[a-zA-Z][a-zA-Z0-9+.-]*:", svc["logoUrl"]),
                         "an absolute logoUrl is concatenated onto the base URL by the provider")

    def test_channel_without_a_logo_gets_no_logo_url(self):
        channels = copy.deepcopy(ONE_CHANNEL)
        del channels["channels"][0]["logo"]
        self.channels_path.write_text(json.dumps(channels))
        self.assertEqual(self.run_generator()["services"][0]["logoUrl"], "")

    def test_english_name_follows_the_channel_and_bare_tags_reuse_it(self):
        langs = self.run_generator()["services"][0]["languages"]
        by_lang = {l["lang"]: l["name"] for l in langs}
        self.assertEqual(by_lang["en"], "Demo One")
        self.assertEqual(by_lang["fr"], "Demo One",
                         "a language entry with no name of its own must reuse the channel name, "
                         "or a rename silently fails to reach the published list")
        self.assertEqual(by_lang["de"], "Demo Eins", "a real translation must be kept")

    def test_radio_channels_keep_their_service_type(self):
        channels = copy.deepcopy(ONE_CHANNEL)
        channels["channels"][0]["type"] = "radio"
        self.channels_path.write_text(json.dumps(channels))
        self.assertEqual(self.run_generator()["services"][0]["type"], "radio")

    def test_instance_is_unicast_dash_at_the_stream(self):
        inst = self.run_generator()["services"][0]["instances"][0]
        self.assertEqual(inst["type"], "dash")
        self.assertEqual(inst["url"], "http://127.0.0.1:3004/one_live/manifest.mpd")
        self.assertTrue(inst["hasAudioDescription"])
        self.assertTrue(inst["hasHardOfHearing"])

    def test_no_channel_is_gated_or_region_restricted(self):
        svc = self.run_generator()["services"][0]
        self.assertEqual(svc["subscriptionPackage"], "",
                         "a subscription package gates the service behind a prompt in the receiver")
        self.assertEqual(svc["targetRegion"], "",
                         "a target region filters the channel out of lists requested for other countries")


class TestProgrammes(GeneratorTestCase):

    def test_series_fields_are_mapped(self):
        prog = self.run_generator()["services"][0]["epgPrograms"][1]
        self.assertEqual(prog["seriesTitle"], "A Series")
        self.assertEqual(prog["seriesNumber"], 2)
        self.assertEqual(prog["episodeNumber"], 4)
        self.assertEqual(prog["catchupUrl"], "https://example.com/catchup/1")

    def test_programme_genre_falls_back_to_the_channel(self):
        progs = self.run_generator()["services"][0]["epgPrograms"]
        self.assertEqual(progs[0]["genre"], "entertainment", "no genre of its own, so the channel's")
        self.assertEqual(progs[1]["genre"], "drama", "its own genre wins")

    def test_programme_image_is_absolute(self):
        prog = self.run_generator()["services"][0]["epgPrograms"][0]
        self.assertEqual(prog["image"], "http://localhost:4000/logos/uploaded/demo-one.png",
                         "content guide images are emitted verbatim, with no base URL applied")


class TestSchemaConstraints(GeneratorTestCase):

    def test_cgsid_is_a_valid_ncname(self):
        """ContentGuideSource/@CGSID is typed xs:ID by the DVB-I schema, so it cannot start
        with a digit. '5g-mag-local-epg' was rejected by schema validation for exactly this."""
        cgsid = self.run_generator()["epg"]["id"]
        self.assertRegex(cgsid, r"^[A-Za-z_][A-Za-z0-9_.-]*$")

    def test_service_uids_are_unique(self):
        uids = [s["uid"] for s in self.run_generator()["services"]]
        self.assertEqual(len(uids), len(set(uids)))


class TestTemplateDrift(unittest.TestCase):
    """The shipped list template is generated from channels.json. Regenerating it is a manual
    step, so nothing otherwise notices when the two drift apart and the template starts
    describing a line-up that no longer exists."""

    # env.sh honours these if they are already set, and load_generator() above sets them to a
    # temporary directory, so they have to be cleared or this test reads another test's fixture.
    LEAKED = ("CHANNELS_FILE", "ADMIN_DIR", "MEDIA_ORIGIN", "ADMIN_ORIGIN")

    def setUp(self):
        clean = {k: v for k, v in os.environ.items() if k not in self.LEAKED}
        out = subprocess.run(
            ["bash", "-c", f'cd "{HERE}" && source env.sh && '
                           'printf "%s\\n%s\\n%s" "$ADMIN_DIR" "$MEDIA_ORIGIN" "$ADMIN_ORIGIN"'],
            capture_output=True, text=True, env=clean)
        if out.returncode != 0:
            self.skipTest(f"env.sh could not be sourced: {out.stderr.strip()}")
        self.admin_dir, self.media_origin, self.admin_origin = out.stdout.strip().split("\n")
        self.shipped = Path(self.admin_dir) / "templates" / "dvbi-local-live-demo.json"
        if not self.shipped.is_file():
            self.skipTest(f"no template at {self.shipped}")

    def test_shipped_template_matches_channels_json(self):
        with tempfile.TemporaryDirectory() as tmp:
            admin = Path(tmp)
            (admin / "templates").mkdir()
            (admin / "config.json").write_text(json.dumps(MINIMAL_CONFIG))
            gen = load_generator(admin, CHANNELS, self.media_origin, self.admin_origin)
            gen.EMIT_TEMPLATE = True
            stdout = sys.stdout
            sys.stdout = open(os.devnull, "w")
            try:
                gen.main()
            finally:
                sys.stdout.close()
                sys.stdout = stdout
            regenerated = json.loads((admin / "templates" / "dvbi-local-live-demo.json").read_text())
        self.assertEqual(
            json.loads(self.shipped.read_text()), regenerated,
            "the shipped template no longer matches channels.json. Regenerate it:\n"
            "  source ./env.sh && ./write-service-list.py --emit-template")


if __name__ == "__main__":
    unittest.main()
