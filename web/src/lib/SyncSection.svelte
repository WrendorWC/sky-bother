<script>
  // Settings → Sync: keep this browser and the Mac app (and your other
  // browsers) in step with a sync code. No accounts; the server only ever
  // holds an encrypted copy.
  import { sync, startSync, stopSync, stopSyncEverywhere } from './syncState.svelte.js';
  import { newCode, format, normalize } from './sync.js';
  import { age } from './format.js';

  let entering = $state(false);
  let typed = $state('');
  let note = $state('');

  let { onjoin, onstart, onsyncnow, joinOnly = false } = $props();
  // In the wizard's first step there's nothing to sync yet: only joining.
  if (joinOnly) entering = true;


  const link = $derived(sync.code ? `${location.origin}/#sync=${normalize(sync.code)}` : '');

  function turnOn() {
    startSync(newCode());
    onstart();
  }
  function join() {
    note = '';
    try {
      const code = format(typed);
      if (normalize(code).length !== 26) throw new Error('A sync code is 26 letters and digits.');
      startSync(code);
      typed = '';
      entering = false;
      onjoin();
    } catch (e) {
      note = e.message;
    }
  }
  async function copy(text, what) {
    try {
      await navigator.clipboard.writeText(text);
      note = `${what} copied.`;
    } catch {
      note = text;
    }
  }
  async function share() {
    try { await navigator.share({ title: 'Sky Bother sync', url: link }); } catch {}
  }
  const canShare = typeof navigator.share === 'function';
  function everywhere() {
    if (confirm('Stop syncing on every device? The synced copy is deleted; each device keeps its own settings.')) stopSyncEverywhere();
  }
</script>

<div class="sync">
  {#if joinOnly}
    <p class="muted">Enter the sync code from Settings → Sync on that device.</p>
    <form onsubmit={e => { e.preventDefault(); join(); }}>
      <input type="text" placeholder="XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XX" bind:value={typed} autocapitalize="characters" autocomplete="off" spellcheck="false" />
      <button type="submit" disabled={!typed.trim()}>Join</button>
    </form>
  {:else if !sync.code}
    <p class="muted">Keep your sites, telescope, settings and plans the same here, on your phone and in the Mac app. No account: one device gets a sync code, the others enter it. Everything is encrypted on the device first.</p>
    <div class="buttons">
      <button type="button" class="primary" onclick={turnOn}>Turn On Sync</button>
      <button type="button" onclick={() => (entering = !entering)}>I Have a Code</button>
    </div>
    {#if entering}
      <form onsubmit={e => { e.preventDefault(); join(); }}>
        <input type="text" placeholder="XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XX" bind:value={typed} autocapitalize="characters" autocomplete="off" spellcheck="false" />
        <button type="submit" disabled={!typed.trim()}>Join</button>
      </form>
      <p class="muted">This browser then takes on the synced settings.</p>
    {/if}
  {:else}
    <p class="code">{format(sync.code)}</p>
    <p class="muted">Enter this code on your other devices (Mac app: Settings → Sync), or open the link there. Keep it private: it's the key to your settings.</p>
    <div class="buttons">
      <button type="button" onclick={() => copy(format(sync.code), 'Code')}>Copy Code</button>
      <button type="button" onclick={() => copy(link, 'Link')}>Copy Link</button>
      {#if canShare}<button type="button" onclick={share}>Share…</button>{/if}
      <button type="button" onclick={onsyncnow} disabled={sync.busy}>{sync.busy ? 'Syncing…' : 'Sync Now'}</button>
    </div>
    <p class="muted">{sync.at ? `Last synced ${age(sync.at)}.` : 'Not synced yet.'}</p>
    <div class="buttons">
      <button type="button" class="link" onclick={stopSync}>Turn Off on This Browser</button>
      <button type="button" class="link danger" onclick={everywhere}>Stop Syncing Everywhere</button>
    </div>
  {/if}
  {#if sync.error}<p class="error">{sync.error}</p>{/if}
  {#if note}<p class="muted">{note}</p>{/if}
</div>

<style>
  .sync { display: grid; gap: 8px; }
  .label { font-weight: 600; }
  p { margin: 0; }
  .buttons { display: flex; gap: 8px; flex-wrap: wrap; }
  form { display: flex; gap: 8px; }
  form input { flex: 1; font-family: ui-monospace, monospace; letter-spacing: 0.04em; }
  .code { font-family: ui-monospace, SFMono-Regular, monospace; font-size: 19px; font-weight: 700; letter-spacing: 0.06em; color: var(--accent); word-break: break-all; }
  .link { background: none; border: none; padding: 0; color: var(--accent); font-weight: 600; }
  .danger { color: var(--poor); }
</style>
