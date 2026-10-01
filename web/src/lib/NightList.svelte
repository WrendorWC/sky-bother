<script>
  // NightListView's rows: score, the night, and its clear dark hours, Moon and cloud.
  import ScoreBadge from './ScoreBadge.svelte';
  import MoonDisc from './MoonDisc.svelte';
  import { weekday, dayAndMonth, hours } from './format.js';

  let { nights, selectedKey = null } = $props();
</script>

<ol class="nights">
  {#each nights as night, index (night.planKey)}
    <li>
      <a href="#/{night.planKey}" class:selected={night.planKey === selectedKey}
         aria-current={night.planKey === selectedKey ? 'page' : undefined}>
        <ScoreBadge score={night.score} size={38} />
        <div class="body">
          <div class="day">
            <strong>{index === 0 ? 'Tonight' : weekday(night.planKey)}</strong>
            <span class="muted-strong">{dayAndMonth(night.planKey)}</span>
          </div>
          <div class="stats muted">
            <span title="Clear dark sky">✦ {hours(night.clearDarkHours)}</span>
            <span title="Moon"><MoonDisc fraction={night.moonIlluminatedFraction} waxing={night.moonIsWaxing} />
              {Math.round(night.moonIlluminatedFraction * 100)}%</span>
            {#if night.hasWeather && night.meanCloudDuringDark != null}
              <span title="Cloud in the dark">☁︎ {Math.round(night.meanCloudDuringDark)}%</span>
            {/if}
          </div>
        </div>
        {#if night.verdict === 'Exceptional'}<span class="sparkle" aria-label="Exceptional">✦</span>{/if}
      </a>
    </li>
  {/each}
</ol>

<style>
  .nights { list-style: none; margin: 0; padding: 0; display: grid; gap: 2px; }
  a {
    display: flex; align-items: center; gap: 12px; padding: 7px 8px; border-radius: 8px;
    color: inherit; text-decoration: none; border: 1px solid transparent;
  }
  a:hover { background: rgba(158, 133, 250, 0.07); }
  a.selected { background: rgba(158, 133, 250, 0.14); border-color: rgba(158, 133, 250, 0.55); }
  .body { flex: 1; min-width: 0; display: grid; gap: 3px; }
  .day { display: flex; gap: 6px; align-items: baseline; }
  .muted-strong { color: var(--muted); }
  .stats { display: flex; gap: 10px; white-space: nowrap; overflow: hidden; }
  .stats span { display: inline-flex; align-items: center; gap: 4px; }
  .sparkle { color: var(--exceptional); font-size: 13px; }
</style>
