# Sky Bother?

*Is the sky worth the bother tonight?*

A Mac app that answers exactly that: whether tonight is worth setting up for, and
what to point at if it is.

It combines four things that normally live in four different tabs:

- **Weather** — hourly cloud cover split into low, mid and high layers, plus dew point, humidity, wind and gusts.
- **Darkness** — real twilight boundaries for your latitude, and the moon's phase, altitude and separation from each target.
- **What's up** — 1,159 deep-sky targets (plus any you add yourself), when each one clears your horizon, and for how long.
- **Your equipment** — whether a target actually fits your frame, and whether it is bright enough to be worth the hours from your sky.

Everything is scored per night and per target, and every score shows its working.

---

## Getting this onto your Mac

You do not need to know git. The three steps below are the whole thing.

**1. Install Xcode** (one time, free, but it is a big download — around 7 GB)

Open the App Store on your Mac, search for **Xcode**, install it. Launch it once
after installing and accept the licence prompt it shows. That is all the setup
Xcode needs.

**2. Download this code**

In your browser, open this repository on GitHub, click the green **Code**
button, then **Download ZIP**. Double-click the downloaded ZIP to unpack it.

You will get a folder containing `SkyBother.xcodeproj`, a `SkyBother` folder and
this README. **Move that folder anywhere you like and rename the outer folder to
anything you like** — `~/Documents/Sky Bother` is a good home. Nothing depends on
where that folder sits or what it is called. (Do leave the inner `SkyBother`
folder named as it is — the project file looks for it by name.)

**3. Build and run it**

Double-click `SkyBother.xcodeproj`. Xcode opens. Press the ▶ Play button in the
top-left (or ⌘R). The first build takes a minute or two; after that it is quick.
The app launches, and a moon icon appears in your menu bar.

To get a normal app you can keep in your Applications folder, choose
**Product → Archive**, or from Terminal run `./build.sh`, which leaves
`SkyBother.app` in a `build` folder — drag that into Applications.

The app is *ad-hoc signed*, which means it builds and runs without an Apple
Developer account. You cannot hand the built app to someone else without more
signing setup, but on your own Mac it just works.

---

## Using it

**Set your site first.** ⌘, opens Settings.

- **Location** — search for your town, or type coordinates directly. Then set two
  things that no API can tell you:
  - **Bortle class** — how light-polluted your sky is, 1 (pristine) to 9 (inner
    city). Look your site up on a light pollution map. This is the single most
    consequential number in the app: it decides whether galaxies are realistic
    for you at all.
  - **Blocked horizon** — how high the trees, houses or hills reach. Targets
    below this are ignored entirely.
- **Equipment** — pick a preset or enter your own numbers. Focal length and
  sensor size give the field of view; aperture and f-ratio drive how fast the
  system is; the dual-band filter toggle changes moon and light-pollution
  handling substantially.
- **Planning** — the thresholds: how much cloud you will tolerate, how dark it
  has to be before an hour counts, how low you will shoot, and how many hours of
  integration you consider a full session.

**Then read the main window.**

- The **left column** is the next week of nights, each with a score, its clear
  dark hours, moon phase and mean cloud.
- The **middle column** is one night. The chart is the heart of it: background
  darkness is the real sky darkness through the night, cloud comes down from the
  top, moonlight washes the background and its altitude is traced along the
  bottom. Every target bar underneath shares that exact time axis, so you can
  read straight down a column to see what is up when.
- The **right column** explains a target: how it sits in your actual frame, its
  altitude curve through the night, and the breakdown of its score.

The **menu bar icon** gives you tonight's verdict and top three targets without
opening anything.

---

## How the scoring works

Both night and target scores are a **weighted geometric mean** of factors in
0...1. Geometric rather than arithmetic on purpose: a single near-zero factor —
no clear sky, no time above the horizon — should sink the result, not be averaged
away by the others.

**Per target** — time on target (0.26), sky darkness (0.18), clear sky (0.18),
framing (0.15), detectability (0.14), altitude (0.09).

**Per night** — clear dark time (0.35), sky clarity (0.30), moon (0.25),
conditions (0.10).

Some deliberate modelling choices worth knowing about:

- **Moonlight costs quality, not clock time.** A bright moon does not shorten the
  night, so darkness windows are set by the Sun alone and the moon is applied as
  a per-target penalty. It scales with phase to the power 2.2 (a half moon is far
  less than half as bright as a full one), with altitude, and with the target's
  angular distance from the moon.
- **A dual-band filter is modelled properly.** On emission nebulae, planetary
  nebulae and supernova remnants it cuts the moon's effect to 40% and adds 2.2
  magnitudes of contrast. This is why the app will happily send you out under a
  gibbous moon for the Crescent Nebula and tell you to forget M51.
- **Detectability is surface brightness against sky background.** The target's
  integrated magnitude is spread over its catalogued ellipse and compared to your
  Bortle sky, adjusted for f-ratio, integration time and filters. This is why
  M101 scores near zero from a city: at roughly 23.8 mag/arcsec² it is fainter
  than a genuinely dark sky, never mind a bright one.
- **Framing is judged against your real sensor.** A target filling 30–80% of the
  frame's long side scores full marks. Smaller wastes the sensor; larger needs a
  mosaic, which is penalised lightly if your rig can do mosaics and heavily if it
  cannot.
- **Alt-az field rotation is accounted for.** For alt-az mounts — which is every
  smart telescope — targets passing near the zenith get a warning, with the peak
  rotation rate in degrees per hour.

---

## Where the data comes from

- **Weather**: [Open-Meteo](https://open-meteo.com) — free, no API key, no
  account. One request per location per refresh.
- **Place search**: Open-Meteo's geocoding API, same terms.
- **Astronomy**: computed locally, no network. Solar position uses the standard
  low-precision Meeus series (accurate to about 0.01°); the moon uses a truncated
  ELP series good to a few arcminutes in position and about a quarter hour in
  phase timing. Rise, set and twilight times are found by sampling the altitude
  on a fixed grid and refining crossings by bisection, which handles circumpolar
  targets and polar summers without special cases.
- **Catalogue**: the complete Messier list, 49 non-Messier showpieces, and
  roughly 1,000 further NGC/IC objects selected by brightness from
  [OpenNGC](https://github.com/mattiaverga/OpenNGC) (CC-BY-SA-4.0) — about
  1,150 targets in total, compiled into the app rather than fetched at
  runtime. Positions are J2000, quoted to about an arcminute. The OpenNGC
  selection is regenerated by `Scripts/build_extended_catalog.py`, not
  hand-typed.
- **Custom targets**: anything still missing can be added by hand from the
  Target Catalog window (the **+** button) — designation, type, position and
  size — and it's scored and planned exactly like a built-in target.

## What this does not do

Stated plainly so you are not left looking for it:

- **No planets, moon or comets as targets.** Planetary ephemerides are a separate
  piece of work and the moon is treated purely as a nuisance light source.
- **No real seeing forecast.** The app shows a rough proxy derived from surface
  gusts. Actual seeing depends on the jet stream, which no free API exposes.
- **No automatic light pollution lookup.** You set the Bortle class by hand.
- **No "use my current location" button.** Location Services on an ad-hoc signed
  app is unreliable; search for your site instead, it is a one-time step.
- **No connection to your telescope.** This plans the session; it does not run it.

## Project layout

```
SkyBother/
  Core/       Angles, Julian dates, coordinates, Sun, Moon, event solving
  Model/      Site, Rig, Target, Preferences
  Catalog/    The 1,159-target built-in catalogue (plus custom targets, saved in Settings)
  Weather/    Open-Meteo forecast and geocoding clients
  Planner/    Sky quality, equipment fit, and the planner that ties it together
  UI/         SwiftUI views, charts and app state
  Support/    Formatting and settings persistence
```

Settings live in `~/Library/Application Support/SkyBother/settings.json`.
Deleting that file resets the app.
