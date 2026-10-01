<script>
  import { verdictColor } from './palette.js';
  let { verdict } = $props();
  const exceptional = $derived(verdict === 'Exceptional');
</script>

<span class="tag" style:color={verdictColor(verdict)}
      style:background={verdictColor(verdict, exceptional ? 0.32 : 0.2)}
      style:border-color={exceptional ? verdictColor(verdict, 0.7) : 'transparent'}>{verdict}</span>

<style>
  .tag { font-size: 14px; font-weight: 600; padding: 3px 10px; border-radius: 999px; border: 1px solid; white-space: nowrap; }
</style>
