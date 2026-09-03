#!/usr/bin/env python3
"""
Pulls a short, real piece of context for as many catalog targets as possible
— discovery history, what makes it notable — straight from each one's
Wikipedia summary (the `extract` field), the same lookup
Scripts/fetch_extended_photos.py already uses for photos. Not written from
memory: if a target has no Wikipedia article, it simply gets no fact, same
as it gets no photo.

Each entry also carries the source article's title and URL, exactly like
TargetImages.json already does for photos — CC-BY-SA-4.0 (Wikipedia's
content license) requires attribution back to the article when its text is
reused, and a bare designation-to-string mapping had no way to show one.

Covers the full catalog — the 159 hardcoded Messier/showpiece entries in
BuiltInCatalog.swift as well as the ~1,000 in ExtendedCatalog.json — writing
results into SkyBother/Catalog/TargetFacts.json (designation -> {fact,
sourceTitle, sourceURL}), loaded at runtime by TargetFactCatalog.swift. Safe
to re-run: entries that already carry all three fields are left untouched
and skipped; anything else (including facts fetched before this script
tracked attribution) is treated as needing a fetch.

Run from the repo root:
    python3 Scripts/fetch_target_facts.py
"""
import json
import re
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
CATALOG_SWIFT = REPO_ROOT / "SkyBother" / "Catalog" / "BuiltInCatalog.swift"
EXTENDED_JSON = REPO_ROOT / "SkyBother" / "Catalog" / "ExtendedCatalog.json"
FACTS_JSON = REPO_ROOT / "SkyBother" / "Catalog" / "TargetFacts.json"

HEADERS = {"User-Agent": "SkyBotherApp/1.0 (https://github.com/WrendorWC/sky-bother; catalog fact fetch)"}
REQUEST_DELAY_SECONDS = 0.15
MAX_FACT_LENGTH = 320


def hardcoded_targets():
    """(designation, commonName-or-None) for every Target(...) literal in
    BuiltInCatalog.swift."""
    text = CATALOG_SWIFT.read_text()
    pattern = re.compile(r'Target\(designation:\s*"([^"]+)",\s*commonName:\s*(nil|"([^"]+)")')
    results = []
    for match in pattern.finditer(text):
        designation = match.group(1)
        common_name = match.group(3)  # None if commonName was `nil`
        results.append((designation, common_name))
    return results


def extended_targets():
    data = json.loads(EXTENDED_JSON.read_text())
    return [(t["designation"], t.get("commonName")) for t in data]


def summary_for(title: str):
    url = f"https://en.wikipedia.org/api/rest_v1/page/summary/{urllib.parse.quote(title.replace(' ', '_'))}"
    req = urllib.request.Request(url, headers=HEADERS)
    try:
        with urllib.request.urlopen(req, timeout=15) as response:
            body = json.loads(response.read())
    except (urllib.error.HTTPError, urllib.error.URLError):
        return None
    # A bare designation like "M1" or "M10" is exactly the kind of short,
    # generic title Wikipedia disambiguation pages exist for (tanks, bus
    # routes, highways...) — that's a failed lookup for our purposes, not a
    # successful one, even though the API returns a normal-looking summary
    # (its own short "X may refer to:" blurb) rather than an error.
    if body.get("type") == "disambiguation" or "may refer to" in body.get("extract", ""):
        return None
    return body


def messier_title(designation: str):
    match = re.fullmatch(r"M\s*0*(\d+)", designation)
    return f"Messier {match.group(1)}" if match else None


def clean_extract(extract: str):
    extract = extract.strip()
    if not extract or len(extract) < 20:
        return None
    if len(extract) <= MAX_FACT_LENGTH:
        return extract
    truncated = extract[:MAX_FACT_LENGTH]
    # The last ". " whose preceding word is more than a couple of letters —
    # skips right past a run of initials like "...William Herschel. J. L.
    # E." (almost always the astronomer/cataloguer J. L. E. Dreyer), which a
    # plain "last '. '" search happily cuts the name in the middle of.
    best = None
    for match in re.finditer(r"\. ", truncated):
        preceding_word = re.split(r"\s+", truncated[:match.start()])[-1]
        if len(preceding_word) > 3:
            best = match.start()
    if best is not None and best > 40:
        return truncated[:best + 1]
    return truncated.rsplit(" ", 1)[0] + "…"


def needs_fetch(entry) -> bool:
    return not (isinstance(entry, dict) and entry.get("fact") and entry.get("sourceURL"))


def main():
    targets = hardcoded_targets() + extended_targets()
    facts = json.loads(FACTS_JSON.read_text()) if FACTS_JSON.exists() else {}

    added = 0
    checked = 0
    for designation, common_name in targets:
        if designation in facts and not needs_fetch(facts[designation]):
            continue
        checked += 1

        # Try, in order: the bare designation, its common name (if any), and
        # — for a plain "M#" designation, which is exactly the ambiguous
        # short title that lands on a disambiguation page — Wikipedia's own
        # unambiguous "Messier N" form. First one that resolves to a real
        # article wins.
        attempts = [designation]
        if common_name:
            attempts.append(common_name)
        alt = messier_title(designation)
        if alt:
            attempts.append(alt)

        summary = None
        for attempt in attempts:
            summary = summary_for(attempt)
            time.sleep(REQUEST_DELAY_SECONDS)
            if summary is not None and "extract" in summary:
                break

        extract = summary.get("extract") if summary else None
        fact = clean_extract(extract) if extract else None
        if not fact:
            continue

        source_url = summary.get("content_urls", {}).get("desktop", {}).get("page")
        source_title = summary.get("title")
        if not source_url or not source_title:
            continue

        facts[designation] = {"fact": fact, "sourceTitle": source_title, "sourceURL": source_url}
        added += 1
        if added % 25 == 0:
            print(f"...{added} facts fetched so far ({checked} checked)")
            FACTS_JSON.write_text(json.dumps(facts, indent=2, ensure_ascii=False, sort_keys=True) + "\n")

    FACTS_JSON.write_text(json.dumps(facts, indent=2, ensure_ascii=False, sort_keys=True) + "\n")
    print(f"Done: {added} facts fetched out of {checked} targets checked ({len(facts)} total in TargetFacts.json).")


if __name__ == "__main__":
    main()
