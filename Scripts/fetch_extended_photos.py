#!/usr/bin/env python3
"""
Fills in photos for the extended catalog (SkyBother/Catalog/ExtendedCatalog.json)
wherever a real one exists — queries Wikipedia's summary API per target, and
only writes an entry when that target actually has a dedicated article with a
thumbnail. Most of the ~1000 extended objects won't (only the famous ones get
a Wikipedia page), so partial coverage is expected, not a bug.

Downloads thumbnails into SkyBother/Catalog/Images/ and merges new entries
into SkyBother/Catalog/TargetImages.json, in exactly the shape
TargetImageCatalog.swift already expects — same as the 153 existing entries,
just sourced automatically instead of by hand. Safe to re-run: existing
entries (by designation) are left untouched and skipped.

Run from the repo root:
    python3 Scripts/fetch_extended_photos.py
"""
import json
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
CATALOG_JSON = REPO_ROOT / "SkyBother" / "Catalog" / "ExtendedCatalog.json"
IMAGES_JSON = REPO_ROOT / "SkyBother" / "Catalog" / "TargetImages.json"
IMAGES_DIR = REPO_ROOT / "SkyBother" / "Catalog" / "Images"

HEADERS = {"User-Agent": "SkyBotherApp/1.0 (https://github.com/WrendorWC/sky-bother; catalog photo fetch)"}
REQUEST_DELAY_SECONDS = 0.15


def summary_for(title: str):
    url = f"https://en.wikipedia.org/api/rest_v1/page/summary/{urllib.parse.quote(title.replace(' ', '_'))}"
    req = urllib.request.Request(url, headers=HEADERS)
    try:
        with urllib.request.urlopen(req, timeout=15) as response:
            return json.loads(response.read())
    except (urllib.error.HTTPError, urllib.error.URLError):
        return None


def download(url: str, destination: Path):
    req = urllib.request.Request(url, headers=HEADERS)
    with urllib.request.urlopen(req, timeout=20) as response:
        destination.write_bytes(response.read())


def main():
    catalog = json.loads(CATALOG_JSON.read_text())
    images = json.loads(IMAGES_JSON.read_text()) if IMAGES_JSON.exists() else {}
    IMAGES_DIR.mkdir(parents=True, exist_ok=True)

    added = 0
    checked = 0
    for target in catalog:
        designation = target["designation"]
        if designation in images:
            continue
        checked += 1

        summary = summary_for(designation)
        time.sleep(REQUEST_DELAY_SECONDS)
        if summary is None or "thumbnail" not in summary:
            common_name = target.get("commonName")
            summary = summary_for(common_name) if common_name else None
            time.sleep(REQUEST_DELAY_SECONDS)
        if summary is None or "thumbnail" not in summary:
            continue

        thumb_url = summary["thumbnail"]["source"]
        extension = Path(urllib.parse.urlparse(thumb_url).path).suffix or ".jpg"
        file_name = f"{designation.replace(' ', '')}{extension}"

        try:
            download(thumb_url, IMAGES_DIR / file_name)
        except (urllib.error.HTTPError, urllib.error.URLError):
            continue

        source_title = summary.get("titles", {}).get("normalized") or summary.get("title") or designation
        source_url = summary.get("content_urls", {}).get("desktop", {}).get("page") \
            or f"https://en.wikipedia.org/wiki/{urllib.parse.quote(designation.replace(' ', '_'))}"

        images[designation] = {"file": file_name, "sourceTitle": source_title, "sourceURL": source_url}
        added += 1
        if added % 25 == 0:
            print(f"...{added} photos found so far ({checked} checked)")
            IMAGES_JSON.write_text(json.dumps(images, indent=2, ensure_ascii=False, sort_keys=True) + "\n")

    IMAGES_JSON.write_text(json.dumps(images, indent=2, ensure_ascii=False, sort_keys=True) + "\n")
    print(f"Done: {added} new photos added out of {checked} extended-catalog targets checked "
          f"({len(images)} total in TargetImages.json).")


if __name__ == "__main__":
    main()
