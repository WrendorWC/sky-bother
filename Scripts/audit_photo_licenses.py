#!/usr/bin/env python3
"""
Verifies the actual license of every photo in TargetImages.json against
Wikipedia/Commons' own metadata, rather than assuming "Wikipedia only hosts
appropriately licensed media" covers it. For each entry: finds the real
lead-image filename behind the article (`pageimages`), then reads that
file's license (`imageinfo`, `extmetadata`) — the same file-resolution path
that correctly follows through to Commons for the shared-repository photos,
which is the large majority of what's in this catalog.

Flags anything that isn't a recognized free license (public domain, CC0, or
a CC-BY / CC-BY-SA variant) as needing manual review — chiefly the rare
"fair use" images Wikipedia hosts locally under its non-free-content policy,
which are licensed for encyclopedic use only and are not clear to redistribute
in a separate app.

Writes a report to Scripts/photo_license_audit.json. Doesn't change
TargetImages.json or touch the app itself — this is a verification pass, to
be read and acted on by hand.

Run from the repo root:
    python3 Scripts/audit_photo_licenses.py
"""
import json
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
IMAGES_JSON = REPO_ROOT / "SkyBother" / "Catalog" / "TargetImages.json"
REPORT_JSON = REPO_ROOT / "Scripts" / "photo_license_audit.json"

HEADERS = {"User-Agent": "SkyBotherApp/1.0 (https://github.com/WrendorWC/sky-bother; license audit)"}
REQUEST_DELAY_SECONDS = 0.15

FREE_LICENSE_PREFIXES = ("cc-", "cc0", "pd", "public domain")


def api_get(params):
    url = "https://en.wikipedia.org/w/api.php?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers=HEADERS)
    try:
        with urllib.request.urlopen(req, timeout=15) as response:
            return json.loads(response.read())
    except (urllib.error.HTTPError, urllib.error.URLError):
        return None


def lead_image_filename(article_title: str):
    body = api_get({
        "action": "query", "titles": article_title,
        "prop": "pageimages", "piprop": "name", "format": "json",
    })
    if not body:
        return None
    pages = body.get("query", {}).get("pages", {})
    for page in pages.values():
        name = page.get("pageimage")
        if name:
            return name
    return None


def license_for_file(filename: str):
    body = api_get({
        "action": "query", "titles": f"File:{filename}",
        "prop": "imageinfo", "iiprop": "extmetadata", "format": "json",
    })
    if not body:
        return None
    pages = body.get("query", {}).get("pages", {})
    for page in pages.values():
        info = page.get("imageinfo")
        if not info:
            continue
        meta = info[0].get("extmetadata", {})
        return {
            "licenseShortName": meta.get("LicenseShortName", {}).get("value"),
            "license": meta.get("License", {}).get("value"),
            "usageTerms": meta.get("UsageTerms", {}).get("value"),
            "restrictions": meta.get("Restrictions", {}).get("value"),
        }
    return None


def is_free(license_info) -> bool:
    if not license_info:
        return False
    if license_info.get("restrictions"):
        return False
    license_code = (license_info.get("license") or "").lower()
    usage_terms = (license_info.get("usageTerms") or "").lower()
    return license_code.startswith(FREE_LICENSE_PREFIXES) or "public domain" in usage_terms


def main():
    entries = json.loads(IMAGES_JSON.read_text())
    report = {}
    needs_review = []

    checked = 0
    for designation, info in entries.items():
        checked += 1
        article_title = info["sourceTitle"]

        filename = lead_image_filename(article_title)
        time.sleep(REQUEST_DELAY_SECONDS)
        if not filename:
            report[designation] = {"status": "no_lead_image_found", "article": article_title}
            needs_review.append(designation)
            continue

        license_info = license_for_file(filename)
        time.sleep(REQUEST_DELAY_SECONDS)
        free = is_free(license_info)
        report[designation] = {
            "status": "free" if free else "NEEDS_REVIEW",
            "article": article_title,
            "file": filename,
            "license": license_info,
        }
        if not free:
            needs_review.append(designation)

        if checked % 50 == 0:
            print(f"...{checked}/{len(entries)} checked, {len(needs_review)} flagged so far")

    REPORT_JSON.write_text(json.dumps(report, indent=2, ensure_ascii=False, sort_keys=True) + "\n")
    print(f"Done: {checked} images checked, {len(needs_review)} need manual review.")
    if needs_review:
        print("Flagged designations:", ", ".join(needs_review))
    print(f"Full report written to {REPORT_JSON}")


if __name__ == "__main__":
    main()
