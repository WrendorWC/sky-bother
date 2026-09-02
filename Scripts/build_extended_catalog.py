#!/usr/bin/env python3
"""
Regenerates SkyBother/Catalog/ExtendedCatalog.json from the OpenNGC database
(https://github.com/mattiaverga/OpenNGC, CC-BY-SA-4.0) — the ~1000 brightest
NGC/IC deep-sky objects not already covered by the app's built-in Messier +
showpieces list in BuiltInCatalog.swift.

Downloads NGC.csv fresh each run rather than vendoring a copy, so the
selection can be regenerated later if the upstream data improves. Run from
the repo root:

    python3 Scripts/build_extended_catalog.py
"""
import csv
import json
import re
import urllib.request
from pathlib import Path

NGC_CSV_URL = "https://raw.githubusercontent.com/mattiaverga/OpenNGC/master/database_files/NGC.csv"

# OpenNGC type code -> the app's TargetType raw value (Model/Target.swift).
# Star/double-star/association/nova/nonexistent/duplicate/other entries aren't
# real imaging targets; dark nebulae ("DrkN") and the ambiguous generic "Neb"
# have no home in the app's (emission-based) surface-brightness model, so both
# are left out rather than guessed at.
TYPE_MAP = {
    "OCl": "openCluster",
    "GCl": "globularCluster",
    "G": "galaxy",
    "GPair": "galaxyGroup",
    "GTrpl": "galaxyGroup",
    "GGroup": "galaxyGroup",
    "PN": "planetaryNebula",
    "HII": "emissionNebula",
    "EmN": "emissionNebula",
    "RfN": "reflectionNebula",
    "SNR": "supernovaRemnant",
    "Cl+N": "emissionNebula",
}

TARGET_COUNT = 1000

REPO_ROOT = Path(__file__).resolve().parent.parent
CATALOG_SWIFT = REPO_ROOT / "SkyBother" / "Catalog" / "BuiltInCatalog.swift"
OUTPUT_JSON = REPO_ROOT / "SkyBother" / "Catalog" / "ExtendedCatalog.json"


def normalize(designation: str) -> str:
    """"NGC 7000" / "NGC7000" / "ngc 07000" all collapse to OpenNGC's own
    "NGC7000" form, so exclusion matching doesn't care about spacing or
    leading zeros."""
    match = re.match(r"^(NGC|IC)\s*0*(\d+)$", designation.strip(), re.IGNORECASE)
    if not match:
        return designation.strip().upper()
    prefix, number = match.group(1).upper(), match.group(2)
    return f"{prefix}{int(number):04d}"


# A couple of showpieces are catalogued under a common name rather than an
# NGC/IC designation, so the plain designation match below can't see them —
# their real NGC number is excluded by hand instead. (LMC has no single NGC
# number of its own, so needs no entry here.)
ALIAS_EXCLUSIONS = {"NGC0292"}  # SMC


def existing_designations() -> set[str]:
    """Every designation already hardcoded in BuiltInCatalog.swift (Messier +
    showpieces) — anything matching one of these is skipped."""
    text = CATALOG_SWIFT.read_text()
    found = {normalize(d) for d in re.findall(r'designation: "([^"]+)"', text)}
    return found | ALIAS_EXCLUSIONS


def sexagesimal_to_degrees(value: str, is_ra: bool):
    value = value.strip()
    if not value:
        return None
    sign = -1.0 if value.startswith("-") else 1.0
    parts = value.lstrip("+-").split(":")
    if len(parts) != 3:
        return None
    hours_or_deg, minutes, seconds = (float(p) for p in parts)
    degrees = hours_or_deg + minutes / 60 + seconds / 3600
    if is_ra:
        degrees *= 15  # hours -> degrees
    return sign * degrees


def pick_common_name(field: str):
    if not field:
        return None
    first = field.split(",")[0].strip()
    return first or None


def app_designation(ngc_name: str):
    """"NGC0007000" -> "NGC 7000", "IC0000434" -> "IC 434" — the spaced,
    unpadded form every existing catalog entry already uses. Returns None for
    sub-component entries like "IC0080 NED01" (part of a multi-galaxy blend),
    which aren't a single coherent target to point a camera at."""
    prefix, digits = ("NGC", ngc_name[3:]) if ngc_name.startswith("NGC") else ("IC", ngc_name[2:])
    if not digits.isdigit():
        return None
    return f"{prefix} {int(digits)}"


def main():
    print(f"Downloading {NGC_CSV_URL} ...")
    with urllib.request.urlopen(NGC_CSV_URL, timeout=30) as response:
        raw = response.read().decode("utf-8")

    excluded = existing_designations()
    rows = list(csv.DictReader(raw.splitlines(), delimiter=";"))
    candidates = []

    for row in rows:
        mapped_type = TYPE_MAP.get(row["Type"].strip())
        if mapped_type is None:
            continue

        name = row["Name"].strip()
        if normalize(name) in excluded:
            continue
        if row["M"].strip():
            continue  # already in BuiltInCatalog.messier

        major_axis = row["MajAx"].strip()
        if not major_axis or float(major_axis) <= 0:
            continue

        magnitude_source = row["V-Mag"].strip() or row["B-Mag"].strip()
        if not magnitude_source:
            continue

        ra = sexagesimal_to_degrees(row["RA"], is_ra=True)
        dec = sexagesimal_to_degrees(row["Dec"], is_ra=False)
        if ra is None or dec is None:
            continue

        designation = app_designation(name)
        if designation is None:
            continue

        minor_axis = row["MinAx"].strip()

        candidates.append({
            "designation": designation,
            "commonName": pick_common_name(row["Common names"]),
            "type": mapped_type,
            "rightAscension": round(ra, 4),
            "declination": round(dec, 4),
            "magnitude": float(magnitude_source),
            "majorAxisArcminutes": float(major_axis),
            "minorAxisArcminutes": float(minor_axis) if minor_axis else float(major_axis),
            "constellation": row["Const"].strip(),
        })

    candidates.sort(key=lambda t: t["magnitude"])
    selected = candidates[:TARGET_COUNT]

    OUTPUT_JSON.write_text(json.dumps(selected, indent=2, ensure_ascii=False) + "\n")
    print(f"Wrote {len(selected)} targets to {OUTPUT_JSON}")
    print(f"({len(candidates)} eligible candidates found among {len(rows)} OpenNGC rows)")


if __name__ == "__main__":
    main()
