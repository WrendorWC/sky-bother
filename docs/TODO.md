# Sky Bother to-do

## Make www.skybother.com the main address (planned for Monday 2026-10-05)

Jon wants the address bar to show www.skybother.com. A browser keeps the web app's settings and
sync code per exact address, so pick one main address and redirect the other — now www.

1. Cloudflare (walk Jon through it): delete the existing `www` DNS record (it blocked adding the
   domain before); Workers & Pages → skybother → Settings → Domains & Routes → add custom domain
   `www.skybother.com`; replace the "Redirect from WWW to root" rule with root → www, leaving
   `/api/*` out of the redirect so sync and the MET Norway proxy keep working on either host.
2. Code: the Mac's web addresses → www — `Support/Persistence.swift` (setup link),
   `Support/SyncClient.swift` (sync API base), `UI/SyncController.swift` (sync link/QR), the
   Settings → Sync caption in `UI/SettingsView.swift`; web comments in `setupLink.js`,
   `weather.js`, and the MET Norway User-Agent in `web/worker/index.js`. Build, install, push.
3. Each browser rejoins sync once at the new address (its old copy stays with skybother.com).

## Web version, alongside the Mac app

Planned 2026-09-25, to start the following week. Full plan: `docs/web-app-plan.md` (approach,
what doesn't survive, phases, ~16–24 sessions). Hosting steps for Jon: `docs/hosting-the-web-app.md`.

**Done so far:** Cloudflare account created; `skybother.com` registered at Cloudflare.

**Next:** Phase 0 — compile the engine to WebAssembly, check its scores match the Mac app
exactly, and test which data services a browser can call directly.
