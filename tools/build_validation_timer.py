#!/usr/bin/env python3
"""Package the isolated read-only hardware validation helper, outside release drivers."""

from datetime import datetime
from pathlib import Path
import xml.etree.ElementTree as ET
from zipfile import ZipFile, ZIP_DEFLATED

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "tools/validation_timer"


def build():
    now = datetime.now()
    xml = ET.parse(SOURCE / "driver.xml").getroot()
    xml.find("version").text = now.strftime("%Y%m%d")
    xml.find("modified").text = now.strftime("%m/%d/%Y %I:%M %p")
    assert xml.findtext("combo") == "true" and xml.find("proxies") is None
    assert xml.find("connections") is None
    destination = ROOT / "dist/validation/schlage_validation_timer.c4z"
    destination.parent.mkdir(parents=True, exist_ok=True)
    with ZipFile(destination, "w", compression=ZIP_DEFLATED) as archive:
        archive.writestr("driver.xml", ET.tostring(xml, encoding="utf-8"))
        archive.writestr("driver.lua", (SOURCE / "driver.lua").read_bytes())
        archive.writestr("www/licenses/LICENSE", (ROOT / "LICENSE").read_bytes())
        archive.writestr(
            "www/documentation/index.html",
            """<!doctype html>
<html><head><meta charset="utf-8"><title>Schlage Validation Timer</title></head>
<body><h1>Schlage Validation Timer</h1>
<p>Development-only read-only measurement. No account access, network requests,
persistence, lock commands, or bindings.</p>
<ol><li>Add this helper to the same controller project as Schlage Account.</li>
<li>Run Start Probe. It measures 100 ms timer callbacks for 15 seconds.</li>
<li>Immediately switch to Schlage Account and run Sign In during that window.</li>
<li>After 15 seconds, return to the probe Properties and record all results.
The result also prints in its Lua tab. Record the account sign-in log timestamp
so overlap with the probe window is established.</li></ol>
<p>Start Probe replaces an earlier run. Stop Probe cancels a run. Results are
measurements, not an automatic pass verdict. Remove the helper after validation.</p>
<p>Copyright 2026 control4-schlage contributors. AGPL-3.0.</p></body></html>""",
        )
    print(destination)


if __name__ == "__main__":
    build()
