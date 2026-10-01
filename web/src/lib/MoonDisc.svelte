<script>
  // MoonPhaseDisc: the lit part of the Moon, lit from the right while waxing.
  let { fraction, waxing, size = 12 } = $props();

  const r = $derived(size / 2);
  // The terminator is a half-ellipse whose width runs from r (new/full) to 0 (quarter).
  const path = $derived.by(() => {
    const rx = Math.abs(1 - 2 * fraction) * r;
    const litRight = waxing;
    const outer = litRight ? 1 : 0;           // sweep for the lit limb
    const inner = (fraction > 0.5) === litRight ? 1 : 0;   // crescent: bulges toward the lit limb
    return `M ${r} 0 A ${r} ${r} 0 0 ${outer} ${r} ${size} A ${rx} ${r} 0 0 ${inner} ${r} 0 Z`;
  });
</script>

<svg width={size} height={size} viewBox="0 0 {size} {size}" aria-hidden="true">
  <circle cx={r} cy={r} r={r - 0.5} fill="rgba(255,255,255,0.12)" />
  {#if fraction > 0.01}<path d={path} fill="rgb(250, 237, 189)" />{/if}
</svg>

<style>svg { flex: none; display: inline-block; vertical-align: -1px; }</style>
