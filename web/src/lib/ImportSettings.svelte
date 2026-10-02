<script>
  // The Mac app's settings file (File → Export Settings… there), read whole:
  // the current site and rig, preferences and custom targets, and the saved
  // sites, saved rigs and plans with them (StoredSettings).
  // `bare`: without its heading, under one of Settings' own.
  let { onimport, bare = false } = $props();
  let error = $state('');

  async function read(event) {
    const file = event.currentTarget.files?.[0];
    event.currentTarget.value = '';
    if (!file) return;
    error = '';
    try {
      const stored = JSON.parse(await file.text());
      if (!stored.site || !stored.rig || !stored.preferences) throw new Error('That isn’t a Sky Bother settings file.');
      onimport({
        site: stored.site,
        rig: stored.rig,
        preferences: stored.preferences,
        customTargets: stored.customTargets ?? [],
        savedSites: stored.savedSites ?? [],
        savedRigs: stored.savedRigs ?? [],
        sessionPlans: stored.sessionPlans ?? {},
      });
    } catch (e) {
      error = e instanceof SyntaxError ? 'That file isn’t readable as Sky Bother settings.' : e.message;
    }
  }
</script>

<div class="import">
  {#if !bare}<span class="label">From the Mac app</span>{/if}
  <label class="button">
    Import Mac Settings File
    <!-- No accept filter: with one, macOS greys every file out while it
         works out their types (slowly, in iCloud folders). The contents are
         checked when it's read. -->
    <input type="file" onchange={read} hidden />
  </label>
  <p class="muted">
    Brings over everything: your site, saved locations, telescope and saved rigs, and every setting.
    Save the file on the Mac with File → Export Settings…. For a phone, File → Copy Web Setup Link is quicker.
  </p>
  {#if error}<p class="error">{error}</p>{/if}
</div>

<style>
  .import { display: grid; gap: 6px; justify-items: start; }
  .label { font-weight: 600; }
  p { margin: 0; }
</style>
