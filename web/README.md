# Sky Bother on the web

The web version, built alongside the Mac app (see `docs/web-app-plan.md`). The
scoring and planning engine is the Mac app's own Swift, compiled to
WebAssembly, so both apps give the same scores.

```
web/
  engine/           Swift package: SkyBother/Core, Planner, Model… symlinked in, plus a JSON API
  build-engine.sh   engine → public/engine.wasm (checked in: Cloudflare can't build Swift)
  public/           engine.wasm, catalog-extended.json
  src/              Svelte page; the engine runs in a Web Worker (src/engine)
  src/lib/          the page's views, each named after the Mac view it ports
  fixtures/         recorded forecasts for the parity check (local/ is gitignored)
  scripts/          parity.mjs, record-fixtures.mjs
```

## Everyday commands

```sh
cd web
npm install
npm run dev            # http://localhost:5173
npm run build:engine   # after changing any shared Swift
npm run parity         # Mac engine vs WebAssembly engine on every fixture
```

`build:engine` needs the swift.org 6.4.0 toolchain (installed per-user in
~/Library/Developer/Toolchains), its WebAssembly SDK
(`swift sdk install …/swift-6.4.0-RELEASE_wasm.artifactbundle.tar.gz`) and
`brew install binaryen`.

## Parity

`npm run parity` runs each `fixtures/*.request.json` through the native engine
(`engine-cli`, the same Swift the Mac app compiles) and through `engine.wasm`.
Nights, targets, order, verdicts and text must match exactly; numbers to 1e-9.
They can't match to the last bit: Apple's maths library and WebAssembly's
round the last bit of sin/cos differently, about 1e-14 on a 0–100 score.

To check your own site, copy the Mac app's settings into a gitignored fixture
(`fixtures/local/`), see `record-fixtures.mjs` for the request shape.

## Size

Foundation on WebAssembly carries all of ICU's data (34 MB). The engine only
needs time zones and English dates, so `engine/Scripts/slim_icu.py` keeps 36
of ICU's 4,855 data items (1.7 MB). If the engine starts needing something it
dropped, parity fails; add the item to `KEEP` there. Result: 14.9 MB raw,
3.9 MB over the wire with Brotli.

## DateFormatter doesn't work in WebAssembly

`DateFormatter` traps in the Wasm build of Foundation, with or without the
slimmed ICU data. Engine code that makes text must use `Format.time` (built
from `Calendar` components) or similar, never a `DateFormatter`. Parity
catches it: the Wasm run fails with `RuntimeError: unreachable`. To see where,
run parity on the unstripped build, whose stack has Swift names:
`node scripts/parity.mjs engine/.build/out/Products/Release-webassembly-wasm32/engine-wasm.wasm`.
