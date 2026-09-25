# Sky Bother on the web — assessment and plan

## Context

Sky Bother is a macOS-only SwiftUI app (~21,800 lines of Swift + 2 Metal shaders). You want a
web version **alongside** the Mac app to reach Windows/Linux users, work on phones and tablets
at the scope, let testers try it from a link (no Gatekeeper, no notarization), and ship fixes
instantly. This document sizes that effort, recommends an approach, and lists what can't come
across.

## What the codebase is made of

| Area | Lines | Moves to the web how |
|---|---|---|
| Core (ephemeris, Sun, Moon, coordinates, projection) | 656 | Shared as-is (see approach) |
| Planner (scoring, auto-plan, drafts, dew, shootability) | 2,328 | Shared as-is |
| Model (site, rig, targets, preferences) | 1,044 | Shared as-is |
| Weather (Open-Meteo, MET Norway, GOES cloud map) | 836 | Parsing shared; fetching redone in JS |
| DarkSky (night lights, land cover, parks, better spot) | 1,582 | Math shared; data access redone |
| Catalog (1,159 targets, facts, sky cutouts, resolver) | 1,274 | Data files reused unchanged |
| LiveImage (Seestar connection, frame decode, viewer) | 971 | **Does not survive** (see below) |
| UI (every screen) | 12,784 | **Rebuilt** in web UI |

So roughly **8,000 lines of logic can be reused** and **~13,000 lines of interface are rewritten**.

## Recommended approach

**Share the engine, rebuild the face.**

1. **Compile the engine to WebAssembly from the same Swift source.** Core, Planner, Model and
   the pure parts of Weather/DarkSky are plain Foundation Swift with no UI. Swift 6 has an
   official WebAssembly SDK. Compiling that code for both targets means the Mac and web apps
   give *identical* scores and plans from one codebase, and every scoring fix lands in both.
   - Networking (`URLSession`, `NWConnection`) and formatting stay out of the engine; the web
     side fetches data in JavaScript and hands it to the engine.
   - **Fallback if the spike fails** (binary too big, Foundation gaps): port the engine to
     TypeScript and lock the two together with shared "golden" test cases generated from the
     Swift tests (same inputs → same scores).
2. **Web UI in TypeScript** (Svelte or React; Svelte is lighter for phones), designed
   responsive from the start: a three-column desktop layout that collapses to tabs on a phone.
3. **Sky dome in WebGL.** Port `SkyDome.metal` / `MoonGlobe.metal` to GLSL (they're per-pixel
   shaders, a near-direct translation); the Canvas drawing (paths, brackets, labels) goes to
   Canvas 2D on top.
4. **Sky browser via Aladin Lite** (free JS library from CDS, the same people behind the HiPS
   survey we already use). It streams sky tiles with smooth pan/zoom — better than our
   cutout-based browser, and much less code to write.
5. **A tiny proxy** (Cloudflare Pages Functions in `web/functions/api/`, free tier, deployed with the site) only for services a browser can't
   call directly: MET Norway (needs a custom User-Agent), and any of SIMBAD / ESA WorldCover /
   NASA night-lights that lack CORS headers (to be confirmed in the spike). Open-Meteo, NASA
   GIBS, CDS HiPS and Overpass allow browser calls.
6. **Installable web app (PWA)**: home-screen icon, catalogue/photos/star map cached for
   offline use at a dark site; forecasts refresh when there's signal. Phones can also use GPS
   for the site — a nice improvement over typing a town.
7. **Hosting**: static files on GitHub Pages or Cloudflare Pages + the proxy. Effectively free
   at beta scale. The 40 MB of photos and star map are served lazily, not all up front.

## What does not survive the move

| Feature | Why | What the web version does instead |
|---|---|---|
| **Seestar live stack (Connect to Telescope)** | Browsers can't open raw TCP sockets or send UDP, and a secure (https) page is blocked from reaching devices on your home network | Stays a Mac-app feature. (A small local "bridge" helper could relay it later, but that brings back an install.) |
| **Menu bar score icon** | No such thing in a browser | Installed PWA could show a badge on its icon on some platforms; otherwise none |
| **Apple Maps place search, "Open in Maps"** | MapKit is Apple-only (MapKit JS needs a paid token) | OpenStreetMap search (Nominatim/Photon) + map links; park search is already OSM-based |
| **Separate windows** (Catalog, Sky browser, Help, Live Stack) | Web apps live in one tab | Panels, overlays and routes within the page |
| **Settings in a file on your Mac** | Browsers keep their own storage, per device | Stored in the browser; add Export/Import so a setup can move between Mac and web (accounts/sync would be a separate, bigger project) |
| **Mac-specific polish** (title-bar fixes, window auto-sizing, auto UI scale) | Not applicable | Responsive CSS does this job |
| **Fully offline forecasts** | Same as today — forecasts need internet | Everything else works offline once cached |

Everything else — nights, scores, the planner, Sky View with playback, clouds and Now, Session
View, catalogue, setup wizard, Better Spot Nearby, dew risk — comes across.

## How big an effort

Measured in working sessions like the recent ones:

| Phase | Result | Sessions |
|---|---|---|
| 0. Spike | Engine compiled to WebAssembly, scores for your site match the Mac app; CORS check on each service | 1–2 |
| 1. "Is tonight worth it?" | Nights list, night detail, timeline, target list, catalogue — read-only, phone-friendly. **First shareable link.** | 4–6 |
| 2. At the scope | Sky View (WebGL dome, playback, Now, clouds), Session View tuned for phones | 4–6 |
| 3. Planning | Planner with drag/resize blocks (mouse and touch), setup wizard, settings, Better Spot Nearby | 5–7 |
| 4. Polish | PWA install + offline, export/import with the Mac app, performance on older phones | 2–3 |
| **Total** | | **~16–24 sessions** |

For scale: that's around two-thirds of what the Mac app took to build. The reusable engine
saves a lot; the UI is still a full rebuild, and phone layouts plus touch-driven plan editing
are the most work. Ongoing cost afterwards: each UI feature is built twice (Mac + web), but
scoring and planning changes are made once.

## Recommended first step

Do Phase 0 before committing to the rest: a new `web/` folder in this repo, the engine
compiled to WebAssembly, and a bare page listing your seven nights with scores that match the
Mac app to the point. If WebAssembly disappoints, switch to the TypeScript-port fallback
before any UI is built — the phases after it are the same either way.

Critical files for the shared engine: `SkyBother/Core/*`, `SkyBother/Planner/*`,
`SkyBother/Model/*`, the parsing halves of `SkyBother/Weather/OpenMeteoClient.swift` and
`SkyBother/DarkSky/SkyGlow.swift`; catalogue data `SkyBother/Catalog/*.json`,
`SkyBother/Catalog/StarMap.jpg`, `SkyBother/Catalog/Images/`.

## Notes for next week (engineering detail)

Decisions already made with the user (2026-09-25): web app **alongside** the Mac app; goals are
Windows/Linux reach, phones/tablets in the field, no-install sharing, instant updates.

Phase 0 spike checklist:
- Install the Swift 6 WebAssembly SDK (`swift sdk install …wasm…`); build a `SkyBotherEngine`
  Swift package target that includes only `Core/`, `Planner/`, `Model/` and pure parsing files.
  Expect friction around: `DateFormatter`/`Calendar` time zones (FoundationInternationalization
  may be unavailable → pass UTC offsets in from JS or bundle tzdata), `NSImage`/`CGImage`
  references in model files (move behind protocols), `Bundle.main` catalogue loading (pass JSON
  in from JS instead).
- Expose a small JSON-in/JSON-out API with JavaScriptKit or plain exported C functions:
  `planNights(site, rig, preferences, forecastJSON, now) -> [NightPlan]`,
  `scoreTarget(...)`, `suggestPlan(...)`. Keep the boundary coarse (one call per night) so
  crossing JS↔Wasm is cheap.
- Measure: `.wasm` size (target < 5 MB after `wasm-opt -Oz` and brotli), time to plan 7 nights
  × 1,159 targets in Safari on an iPhone (target < 1 s; run in a Web Worker).
- Parity harness: a small Swift CLI (native) and a Node script (Wasm) produce the same JSON for
  fixed inputs (recorded Open-Meteo responses checked into `web/fixtures/`); diff must be empty.
- CORS probe from a plain page for: api.open-meteo.com, geocoding-api.open-meteo.com,
  api.met.no, gibs.earthdata.nasa.gov, wvs.earthdata.nasa.gov (Black Marble),
  esa-worldcover.s3…amazonaws.com (range reads!), overpass-api.de, simbad (Sesame),
  alasky.cds.unistra.fr hips2fits. Anything failing goes through the Worker proxy.
- Place search replacement: Photon (komoot) or Nominatim (1 req/s policy → via proxy with
  caching). Parks are already Overpass.

UI build notes:
- Svelte + Vite; state in one store mirroring `AppState`; persistence in IndexedDB with a
  versioned schema matching `Persistence.swift` so Export/Import JSON is interchangeable.
- Sky dome: port `SkyDome.metal` stitchable shader to a WebGL2 fragment shader almost line for
  line (same uniforms); `MoonGlobe.metal` likewise. Draw brackets/labels/paths in a Canvas 2D
  overlay; reuse the gnomonic/azimuthal math from `SkyProjection.swift` via the engine.
- Planner drag/resize: pointer events (mouse + touch); reuse `PlanDraft` rules from the engine.
- Keep product rules from memory: simple and guiding (no power-user overrides), title-case
  buttons, sentence-case tooltips, representative clouds labelled, never save live images.
- Mac-only features stay Mac-only: Seestar live stack, menu bar icon.

## Verification (for Phase 0 and every phase after)

- **Score parity:** a test run compares Mac (native) and web (WebAssembly) output — night
  scores, target scores, suggested plans — for several sites (your yards, Namibia, a high-
  latitude site) over a week of forecasts, which must match exactly.
- The existing `SkyBotherTests` keep passing against the shared engine.
- Browser checks in Chrome, Safari and Firefox on desktop, plus Safari on iPhone and Chrome on
  Android, using real forecast data.
- Lighthouse/PWA audit for install and offline behaviour in Phase 4.
