# Hosting the Sky Bother web app for (almost) nothing

This is the checklist for putting the web version of Sky Bother online once it's built. It
assumes the plan in `web-app-plan.md`: a static web app (HTML, JavaScript, a WebAssembly
engine, catalogue data) plus one tiny "proxy" for the few data services a browser can't call
directly.

**Expected cost: $0 a month.** The only optional spend is a custom domain, about $10–12 a
year. Everything below uses free tiers that are far larger than a beta needs.

---

## What you'll set up

| Piece | Service | Cost |
|---|---|---|
| The website itself | **Cloudflare Pages** (recommended) or GitHub Pages | Free |
| The proxy for MET Norway and friends | **Cloudflare Pages Functions** (deploys with the site) | Free (100,000 requests/day) |
| Code and automatic deploys | Your existing GitHub repo `WrendorWC/sky-bother` | Free |
| A nice address (optional) | Cloudflare Registrar, e.g. `skybother.app` | ~$10–12/year |

Why Cloudflare: one account, the site and proxy deploy together on the same
domain (which avoids browser cross-site headaches), unlimited bandwidth on the free plan
(the catalogue photos and star map are ~40 MB, and every visitor downloads some of them),
and it rebuilds the site automatically every time code is pushed to GitHub.

GitHub Pages is a fine alternative for the site (also free, and you already have GitHub), but
it can't run the proxy, and it has a soft 100 GB/month bandwidth limit. Pick Cloudflare unless
you'd rather avoid another account.

---

## Step 1 — Create a Cloudflare account (5 minutes)

1. Go to **dash.cloudflare.com/sign-up** and sign up with your email.
2. Verify the email. Choose the **Free** plan if asked. No credit card is needed.
3. Turn on two-factor authentication: **My Profile → Authentication → Two-Factor**.

## Step 2 — Connect the website to GitHub (10 minutes)

Do this once the `web/` folder exists in the repo (Claude will create it).

1. In the Cloudflare dashboard: **Workers & Pages → Create → Pages → Connect to Git**.
2. Authorize Cloudflare to access GitHub, and give it access to **only** the
   `WrendorWC/sky-bother` repository (choose "Only select repositories").
3. Settings for the project:
   - **Project name:** `skybother` (this becomes `skybother.pages.dev`)
   - **Production branch:** `main`
   - **Framework preset:** None (or Svelte/Vite if offered)
   - **Build command:** `cd web && npm ci && npm run build`
   - **Build output directory:** `web/dist`
   - **Root directory:** leave blank
4. Click **Save and Deploy**. After a minute or two the site is live at
   **https://skybother.pages.dev**.

From then on, every push to `main` redeploys automatically. Pushes to other branches get
their own preview address — handy for letting a tester try something before it's live.

> The WebAssembly engine is built from Swift, which Cloudflare's build machines don't have.
> Claude will set it up so the compiled engine (`web/public/engine.wasm`) is checked into the
> repo, rebuilt on your Mac when the engine changes. Nothing extra for you to install on
> Cloudflare.

## Step 3 — The proxy (nothing to do)

The proxy forwards a handful of requests (MET Norway forecasts, place search, possibly
SIMBAD or NASA night-lights) that browsers aren't allowed to make directly. It's written as
**Cloudflare Pages Functions** — small files in `web/functions/api/` in the repo — so it
deploys automatically with the site in Step 2 and answers at `/api/…` on the same address.
There's no separate Worker to create or route to configure.

Free limit: 100,000 requests a day (shared with Workers). Each visitor uses a few dozen at
most, and responses are cached, so this covers thousands of daily users.

## Step 4 (optional) — Your own domain (~$10–12/year)

1. **Domain Registration → Register Domains**, search for a name (e.g. `skybother.app`,
   `skybother.com`). Cloudflare sells at cost with no markup; `.app` and `.com` are about
   $10–14/year. Pay by card.
2. **Workers & Pages → skybother → Custom domains → Set up a custom domain** → enter it.
   Cloudflare configures DNS and the HTTPS certificate automatically.
3. Turn on auto-renew so the domain doesn't lapse.

Note: `.app` domains require HTTPS, which Cloudflare provides automatically — no action
needed.

## Step 5 — Settings worth changing (5 minutes)

- **Spending safety:** on the Free plan nothing can be charged. Don't upgrade to the $5/month
  Workers "Paid" plan unless Claude says the free limit is being hit.
- **Security → Bots:** leave "Bot Fight Mode" off for the `/api/` route, or the app's own
  requests can be challenged.
- **Web Analytics** (free, privacy-friendly, no cookie banner needed):
  **Analytics & Logs → Web Analytics → Add a site**. Shows how many testers visit.

## Step 6 — Tell the data services who you are

Some free data services ask apps to identify themselves:

- **MET Norway** (backup forecasts): requires a User-Agent with contact info. The proxy
  sends `SkyBother/1.0 https://github.com/WrendorWC/sky-bother` — already what the Mac app
  uses. Nothing to register.
- **Nominatim / OpenStreetMap place search** (replaces Apple Maps): max 1 request per second
  and an identifying User-Agent; the proxy caches and throttles. If usage grows, switch to
  Photon (komoot) or a free tier of a geocoding service.
- **Open-Meteo**: free for non-commercial use without a key. If Sky Bother ever becomes paid
  or donation-funded with significant traffic, check their terms (their commercial plan starts
  around €29/month).

Everything else (NASA GIBS, CDS sky survey, OpenStreetMap Overpass, ESA WorldCover) is free
and needs no account.

---

## What it costs at different sizes

| Visitors | Cost |
|---|---|
| Beta (up to a few hundred people) | **$0** (+ domain if you want one) |
| A few thousand regular users | Still $0 on Cloudflare's free tiers |
| Tens of thousands of daily users | Maybe the $5/month Workers plan; Open-Meteo's terms become the thing to watch |

## Things to know

- **Sharing with testers:** just send the link. On a phone, "Add to Home Screen" makes it
  behave like an app (icon, full screen, works offline once loaded).
- **Updates:** push to GitHub → live within a couple of minutes. Testers get it on their next
  visit; no downloads.
- **The Mac app is unaffected.** It keeps shipping through GitHub Releases as now, and remains
  the only way to get the Seestar live stack and the menu bar icon.
- **Privacy:** nothing is stored on the server. Each person's site, rig and plans live in their
  own browser (with Export/Import to move them), so there are no user accounts or personal
  data to look after.

## Your to-do list, in order

1. ☐ Create the Cloudflare account and turn on two-factor (Step 1).
2. ☐ When Claude says the `web/` folder is ready: connect Pages to GitHub (Step 2).
3. ☐ Optional: buy a domain and attach it (Step 4).
4. ☐ Optional: turn on Web Analytics (Step 5).
