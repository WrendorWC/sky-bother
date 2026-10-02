<script>
  // Help (HelpView on the Mac): topics down the side on a wide screen, a
  // row of them to pick from on a phone, and the chosen topic's sections.
  import { topics } from './help.js';

  let { topic = null } = $props();
  const current = $derived(topics.find(t => t.id === topic) ?? topics[0]);

  $effect(() => {
    current;
    window.scrollTo({ top: 0 });
  });
</script>

<section class="help">
  <header>
    <a class="back" href="#/">‹ Home</a>
    <h2>Help</h2>
  </header>
  <div class="layout">
    <nav aria-label="Help topics">
      {#each topics as t}
        <a href="#/help/{t.id}" class:on={t.id === current.id} aria-current={t.id === current.id ? 'page' : undefined}>{t.title}</a>
      {/each}
    </nav>
    <article class="panel">
      <h3>{current.title}</h3>
      {#each current.sections as section}
        <div class="section">
          {#if section.heading}<h4>{section.heading}</h4>{/if}
          {#each section.body.split('\n\n').filter(Boolean) as paragraph}<p>{paragraph}</p>{/each}
          {#if section.swatches}
            <ul class="swatches">
              {#each section.swatches as [colour, label]}<li><span style:background={colour}></span>{label}</li>{/each}
            </ul>
          {/if}
        </div>
      {/each}
    </article>
  </div>
</section>

<style>
  .help { display: grid; gap: 14px; max-width: 1100px; margin: 0 auto; width: 100%; }
  header { display: grid; gap: 4px; }
  .back { color: var(--accent); text-decoration: none; font-weight: 600; }
  h2 { margin: 0; font-size: 26px; }
  .layout { display: grid; grid-template-columns: 220px minmax(0, 1fr); gap: 20px; align-items: start; }
  nav { display: grid; gap: 2px; position: sticky; top: 72px; }
  nav a { padding: 8px 12px; border-radius: 9px; color: var(--muted); text-decoration: none; font-weight: 600; }
  nav a:hover { color: var(--text); }
  nav a.on { background: rgba(158, 133, 250, 0.2); color: var(--text); }
  article { padding: 20px 24px; border-radius: 14px; display: grid; gap: 18px; }
  h3 { margin: 0; font-size: 22px; }
  .section { display: grid; gap: 6px; }
  h4 { margin: 0; font-size: 16px; color: var(--accent); }
  p { margin: 0; line-height: 1.55; color: var(--text); }
  .swatches { list-style: none; margin: 4px 0 0; padding: 0; display: grid; gap: 7px; }
  .swatches li { display: flex; gap: 10px; align-items: flex-start; line-height: 1.45; }
  .swatches span { flex: none; width: 14px; height: 14px; margin-top: 3px; border-radius: 4px; border: 1px solid rgba(255, 255, 255, 0.2); }
  @media (max-width: 760px) {
    .layout { grid-template-columns: minmax(0, 1fr); }
    /* A strip of topics to swipe along, above the text. */
    nav { position: static; display: flex; gap: 6px; overflow-x: auto; padding-bottom: 4px; scrollbar-width: none; }
    nav a { flex: none; padding: 7px 12px; border: 1px solid var(--panel-border); border-radius: 999px; font-size: 14px; }
    article { padding: 16px; }
  }
</style>
