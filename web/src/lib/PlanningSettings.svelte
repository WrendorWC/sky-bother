<script>
  // Settings → Planning (PlanningSettings on the Mac): the kind of night you
  // want, what counts as usable sky, and what to show. The goal's own
  // numbers sit under "Fine-tune", so the three presets are the first choice.
  import { duration, degrees } from './format.js';

  let { settings, onchange } = $props();

  const prefs = $derived(settings.preferences);
  const setPrefs = fields => onchange({ ...settings, preferences: { ...prefs, ...fields } });

  // GoalPreset (Model/Preferences.swift)
  const goals = [
    { id: 'quickSession', title: 'Quick session', summary: 'About an hour per target.', minutes: 60, emphasis: 'longerIntegration' },
    { id: 'deepIntegration', title: 'Deep integration', summary: 'Several hours on one or two targets.', minutes: 240, emphasis: 'longerIntegration' },
    { id: 'variety', title: 'Variety', summary: 'Many targets, about an hour each.', minutes: 120, emphasis: 'moreTargets' },
  ];
  const goal = $derived(goals.find(g => g.minutes === prefs.integrationGoalMinutes && g.emphasis === prefs.planEmphasis));
  let fineTuning = $state(false);

  // Preferences.sessionCapMinutes / minimumSessionMinutes
  const cap = $derived(prefs.planEmphasis === 'moreTargets' ? Math.max(20, prefs.integrationGoalMinutes / 2) : prefs.integrationGoalMinutes);
  const floor = $derived(prefs.planEmphasis === 'moreTargets' ? 20 : Math.max(30, cap / 3));
  // Kasten & Young air mass (SkyCoordinates.airMass)
  const airMass = altitude => 1 / (Math.sin(altitude * Math.PI / 180) + 0.50572 * Math.pow(altitude + 6.07995, -1.6364));
  const verdictFor = s => (s >= 90 ? 'Exceptional' : s >= 75 ? 'Excellent' : s >= 60 ? 'Good' : s >= 45 ? 'Marginal' : 'Poor');

  // Sliders move freely and apply when let go.
  let draft = $state({});
  const shown = key => draft[key] ?? prefs[key];
  const slide = key => e => (draft = { ...draft, [key]: Number(e.currentTarget.value) });
  const commit = key => e => {
    const value = Number(e.currentTarget.value);
    draft = { ...draft, [key]: undefined };
    setPrefs({ [key]: value });
  };
  const nights = $derived(prefs.forecastNights);
</script>

<div class="pane">
  <div class="group">
    <h3 class="group-title">Kind of night</h3>
    <div class="card">
      <div class="item">
        <div class="seg" role="radiogroup" aria-label="Kind of night">
          {#each goals as g}
            <button type="button" role="radio" aria-checked={goal?.id === g.id} class:on={goal?.id === g.id}
                    onclick={() => setPrefs({ integrationGoalMinutes: g.minutes, planEmphasis: g.emphasis })}>{g.title}</button>
          {/each}
        </div>
        <p class="caption">{goal ? goal.summary : `Custom: up to ${duration(cap)} per target.`}</p>
      </div>
      {#if fineTuning || !goal}
        <label class="item">
          <div class="head"><span class="title">Integration goal</span><span class="value">{duration(shown('integrationGoalMinutes'))}</span></div>
          <input type="range" min="30" max="480" step="15" value={shown('integrationGoalMinutes')} oninput={slide('integrationGoalMinutes')} onchange={commit('integrationGoalMinutes')} />
          <p class="caption">Full marks for time once a target is usable this long.</p>
        </label>
        <div class="item">
          <span class="title">Suggested plan favours</span>
          <div class="seg" role="radiogroup" aria-label="Suggested plan favours">
            <button type="button" role="radio" aria-checked={prefs.planEmphasis !== 'moreTargets'} class:on={prefs.planEmphasis !== 'moreTargets'} onclick={() => setPrefs({ planEmphasis: 'longerIntegration' })}>Longer integration</button>
            <button type="button" role="radio" aria-checked={prefs.planEmphasis === 'moreTargets'} class:on={prefs.planEmphasis === 'moreTargets'} onclick={() => setPrefs({ planEmphasis: 'moreTargets' })}>More targets</button>
          </div>
          <p class="caption">At most {duration(cap)} per target{prefs.planEmphasis === 'moreTargets' ? `, so about twice as many fit, down to ${duration(floor)}` : `, and nothing shorter than ${duration(floor)}`}.</p>
        </div>
      {:else}
        <div class="item inline">
          <p class="caption">Set your own time per target.</p>
          <button type="button" class="text-button" onclick={() => (fineTuning = true)}>Fine-tune</button>
        </div>
      {/if}
    </div>
  </div>

  <div class="group">
    <h3 class="group-title">What counts as usable</h3>
    <div class="card">
      <label class="item">
        <div class="head"><span class="title">Maximum cloud cover</span><span class="value">{shown('maximumCloudCover')}%</span></div>
        <input type="range" min="0" max="100" step="5" value={shown('maximumCloudCover')} oninput={slide('maximumCloudCover')} onchange={commit('maximumCloudCover')} />
        <p class="caption">Hours cloudier than this count less: half for every 6 points over.</p>
      </label>
      <label class="item">
        <div class="head"><span class="title">Minimum darkness</span><span class="value">Sun {Math.round(Math.pow(shown('minimumDarkness'), 1 / 1.4) * 12 + 6)}° down</span></div>
        <input type="range" min="0.1" max="1" step="0.05" value={shown('minimumDarkness')} oninput={slide('minimumDarkness')} onchange={commit('minimumDarkness')} />
        <p class="caption">18° below the horizon is full astronomical darkness. Moonlight is scored separately.</p>
      </label>
      <label class="item">
        <div class="head"><span class="title">Minimum altitude</span><span class="value">{degrees(shown('minimumUsefulAltitude'))}</span></div>
        <input type="range" min="10" max="60" step="5" value={shown('minimumUsefulAltitude')} oninput={slide('minimumUsefulAltitude')} onchange={commit('minimumUsefulAltitude')} />
        <p class="caption">Lower targets are ignored — there you look through {airMass(shown('minimumUsefulAltitude')).toFixed(1)} times as much air as straight up.</p>
      </label>
    </div>
  </div>

  <div class="group">
    <h3 class="group-title">What to show</h3>
    <div class="card">
      <label class="item">
        <div class="head"><span class="title">Hide targets scoring below</span><span class="value">{shown('minimumScore')} · {verdictFor(shown('minimumScore'))}</span></div>
        <input type="range" min="0" max="80" step="5" value={shown('minimumScore')} oninput={slide('minimumScore')} onchange={commit('minimumScore')} />
      </label>
      <div class="item inline">
        <span class="title">Nights ahead</span>
        <div class="stepper">
          <button type="button" aria-label="Fewer nights" disabled={nights <= 1} onclick={() => setPrefs({ forecastNights: nights - 1 })}>−</button>
          <span class="value">{nights}</span>
          <button type="button" aria-label="More nights" disabled={nights >= 14} onclick={() => setPrefs({ forecastNights: nights + 1 })}>+</button>
        </div>
      </div>
      <label class="item inline"><span class="title">Star clusters</span><input class="switch" type="checkbox" checked={prefs.includeStarClusters} onchange={e => setPrefs({ includeStarClusters: e.currentTarget.checked })} /></label>
      <label class="item inline"><span class="title">Bright stars and doubles</span><input class="switch" type="checkbox" checked={prefs.includeStars} onchange={e => setPrefs({ includeStars: e.currentTarget.checked })} /></label>
      <label class="item inline"><span class="title">Visible comets</span><input class="switch" type="checkbox" checked={prefs.includeComets} onchange={e => setPrefs({ includeComets: e.currentTarget.checked })} /></label>
      <label class="item inline">
        <div><span class="title">Targets larger than the frame</span><p class="caption">They'd need a mosaic, or show only in part.</p></div>
        <input class="switch" type="checkbox" checked={prefs.includeOversizedTargets} onchange={e => setPrefs({ includeOversizedTargets: e.currentTarget.checked })} />
      </label>
    </div>
  </div>
</div>

<style>
  .pane { display: grid; gap: 22px; }
  .stepper { display: flex; align-items: center; gap: 12px; }
  .stepper button { width: 36px; height: 32px; padding: 0; font-size: 18px; line-height: 1; }
  .stepper .value { min-width: 2ch; text-align: center; }
</style>
