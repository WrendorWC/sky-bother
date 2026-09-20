#!/usr/bin/env python3
"""Generate sky-survey thumbnails for catalog targets that have no Wikipedia photo.

Most of the ~1000 extended-catalog objects have no Wikipedia image, and those
rows showed a "No Photo Available" placeholder — which told you nothing about
the object. A Digitized Sky Survey cutout tells you what is actually there.

Wikipedia photos win wherever they exist: they are colour images from real
telescopes and simply look better than a photographic-plate scan. This only
fills the gaps, so nothing already illustrated is touched.

Cutouts come from CDS's hips2fits, which renders a patch of an all-sky HiPS
survey to an exact centre and field of view. The documented primary endpoint
(alasky) refuses connections from some networks, so the alaskybis mirror is
tried first with the primary as fallback — the same ordering the app uses.

    python3 Scripts/build_sky_thumbnails.py [--limit N] [--only DESIG ...] [--force]

Resumable: a target whose file already exists is skipped unless --force.
"""

import argparse
import json
import os
import re
import sys
import threading
import time
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOG_DIR = os.path.join(ROOT, "SkyBother", "Catalog")
OUT_DIR = os.path.join(CATALOG_DIR, "SkyThumbnails")
MANIFEST = os.path.join(CATALOG_DIR, "SkyThumbnails.json")

SURVEY = "CDS/P/DSS2/color"
ENDPOINTS = [
    "https://alaskybis.cds.unistra.fr/hips-image-services/hips2fits",
    "https://alasky.cds.unistra.fr/hips-image-services/hips2fits",
]
USER_AGENT = "SkyBotherApp/1.0 (https://github.com/WrendorWC/sky-bother; thumbnail build)"
PIXELS = 256
# Politeness against practicality. Strictly serial, this took about ten
# seconds a target — six hundred of them is an hour and a half — because the
# cost is almost all server-side render time, not bandwidth. Four at a time
# with a gap between each is still a gentle load for a free academic service
# and finishes in a sensible afternoon.
WORKERS = 4
DELAY_SECONDS = 0.25
# A slow render shouldn't hold a worker for the better part of a minute; the
# target is simply retried on the next run, which skips everything already
# fetched.
TIMEOUT_SECONDS = 25


def field_of_view_degrees(major_arcmin):
    """How much sky to show around the object.

    Wider than the catalogued extent, because the catalogue records the object
    rather than the part worth looking at — an open cluster inside a nebula is
    listed as the cluster. But only about twice as wide: a thumbnail has one
    job, which is to make the object recognisable at row size, and the first
    attempt at this floored the field at 12 arcminutes and turned every small
    planetary into an indistinguishable star field. NGC 2392 is 0.8 arcminutes
    across; at 12 it was roughly seventeen pixels of a 256-pixel image.

    The floor is therefore small enough that a tiny object still fills a
    useful part of the frame, and the ceiling generous enough that the big
    showpieces read as themselves rather than as a crop of empty sky.
    """
    arcmin = max(3.0, min(300.0, (major_arcmin or 0) * 2.2))
    return arcmin / 60.0


def load_targets():
    """Every target the app knows: the hand-written Swift ones plus the JSON."""
    targets = []

    swift = open(os.path.join(CATALOG_DIR, "BuiltInCatalog.swift"), encoding="utf-8").read()
    # Entries span three lines; pull the fields that matter off the whole blob.
    for block in re.findall(r"Target\(designation:.*?constellation:\s*\"[^\"]*\"\)", swift, re.S):
        def field(name, pattern=r'([-\d.]+)'):
            m = re.search(name + r':\s*' + pattern, block)
            return m.group(1) if m else None
        designation = re.search(r'designation:\s*"([^"]+)"', block)
        if not designation:
            continue
        targets.append({
            "designation": designation.group(1),
            "rightAscension": float(field("rightAscension") or 0),
            "declination": float(field("declination") or 0),
            "majorAxisArcminutes": float(field("majorAxisArcminutes") or 0),
        })

    with open(os.path.join(CATALOG_DIR, "ExtendedCatalog.json"), encoding="utf-8") as handle:
        targets.extend(json.load(handle))

    seen, unique = set(), []
    for target in targets:
        if target["designation"] in seen:
            continue
        seen.add(target["designation"])
        unique.append(target)
    return unique


def safe_filename(designation):
    return re.sub(r"[^A-Za-z0-9]+", "_", designation).strip("_") + ".jpg"


def fetch(target):
    fov = field_of_view_degrees(target.get("majorAxisArcminutes"))
    params = urllib.parse.urlencode({
        "hips": SURVEY,
        "ra": round(target["rightAscension"], 5),
        "dec": round(target["declination"], 5),
        "fov": round(fov, 5),
        "width": PIXELS,
        "height": PIXELS,
        "format": "jpg",
    })
    last_error = None
    for endpoint in ENDPOINTS:
        request = urllib.request.Request(endpoint + "?" + params, headers={"User-Agent": USER_AGENT})
        try:
            with urllib.request.urlopen(request, timeout=TIMEOUT_SECONDS) as response:
                if response.status != 200:
                    last_error = "HTTP %s" % response.status
                    continue
                data = response.read()
                if len(data) < 1200:
                    # A near-empty JPEG means the survey has nothing there.
                    last_error = "empty (%d bytes)" % len(data)
                    continue
                return data, fov
        except Exception as error:                      # noqa: BLE001
            last_error = str(error)
    return None, last_error


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--limit", type=int, default=0, help="stop after N fetches")
    parser.add_argument("--only", nargs="*", help="just these designations")
    parser.add_argument("--force", action="store_true", help="refetch files already present")
    args = parser.parse_args()

    os.makedirs(OUT_DIR, exist_ok=True)
    photos = json.load(open(os.path.join(CATALOG_DIR, "TargetImages.json"), encoding="utf-8"))
    manifest = {}
    if os.path.exists(MANIFEST):
        manifest = json.load(open(MANIFEST, encoding="utf-8"))

    targets = load_targets()
    if args.only:
        wanted = set(args.only)
        todo = [t for t in targets if t["designation"] in wanted]
    else:
        todo = [t for t in targets if t["designation"] not in photos]

    print("catalog: %d targets, %d already have a Wikipedia photo, %d to fill"
          % (len(targets), len(photos), len([t for t in targets if t["designation"] not in photos])))

    pending = []
    skipped = 0
    for target in todo:
        designation = target["designation"]
        filename = safe_filename(designation)
        if os.path.exists(os.path.join(OUT_DIR, filename)) and not args.force:
            manifest.setdefault(designation, {"file": filename})
            skipped += 1
            continue
        pending.append(target)
    if args.limit:
        pending = pending[:args.limit]
    print("  %d already on disk, %d to fetch" % (skipped, len(pending)))

    lock = threading.Lock()
    done = failed = 0

    def work(target):
        time.sleep(DELAY_SECONDS)
        return target, fetch(target)

    with ThreadPoolExecutor(max_workers=WORKERS) as pool:
        futures = [pool.submit(work, target) for target in pending]
        for future in as_completed(futures):
            target, (data, info) = future.result()
            designation = target["designation"]
            filename = safe_filename(designation)
            with lock:
                if data is None:
                    print("  FAIL %-18s %s" % (designation, info), flush=True)
                    failed += 1
                    continue
                with open(os.path.join(OUT_DIR, filename), "wb") as handle:
                    handle.write(data)
                manifest[designation] = {"file": filename, "fovArcminutes": round(info * 60, 1)}
                done += 1
                if done % 25 == 0:
                    print("  %d fetched, %d failed" % (done, failed), flush=True)
                    with open(MANIFEST, "w", encoding="utf-8") as handle:
                        json.dump(manifest, handle, indent=1, sort_keys=True)

    # Reconcile before writing. A run that dies mid-flight leaves files on
    # disk whose manifest entries were never checkpointed, and those images
    # then ship in the bundle while the app still shows a placeholder for
    # them — present but unreachable. Rebuilding every entry from what is
    # actually on disk makes the manifest a description of the folder rather
    # than a log of what this particular run happened to do.
    manifest = {}
    for target in targets:
        designation = target["designation"]
        if designation in photos:
            continue
        filename = safe_filename(designation)
        if not os.path.exists(os.path.join(OUT_DIR, filename)):
            continue
        manifest[designation] = {
            "file": filename,
            "fovArcminutes": round(field_of_view_degrees(target.get("majorAxisArcminutes")) * 60, 1),
        }

    with open(MANIFEST, "w", encoding="utf-8") as handle:
        json.dump(manifest, handle, indent=1, sort_keys=True)
    print("done: %d fetched, %d skipped, %d failed, %d in manifest"
          % (done, skipped, failed, len(manifest)))


if __name__ == "__main__":
    sys.exit(main())
