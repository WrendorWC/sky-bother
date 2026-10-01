<script>
  // TargetThumbnail: the target's picture, or a quiet placeholder sky.
  import { targetImage } from './images.js';

  let { designation, size = 56, label = null } = $props();
  const image = $derived(targetImage(designation));
</script>

<span class="thumb" style:width="{size}px" style:height="{size}px">
  {#if image}
    <img src={image.url} alt={label ?? designation} loading="lazy" decoding="async" />
  {:else}
    <span class="placeholder" aria-label="No photo available"></span>
  {/if}
</span>

<style>
  .thumb {
    flex: none; display: block; overflow: hidden; border-radius: 8px;
    border: 1px solid var(--panel-border); background: var(--space-top);
  }
  img { width: 100%; height: 100%; object-fit: cover; display: block; }
  .placeholder {
    display: block; width: 100%; height: 100%;
    background:
      radial-gradient(1px 1px at 22% 30%, rgba(255,255,255,0.7), transparent),
      radial-gradient(1px 1px at 68% 58%, rgba(255,255,255,0.5), transparent),
      radial-gradient(1px 1px at 40% 78%, rgba(255,255,255,0.4), transparent),
      linear-gradient(var(--space-top), #21143d);
  }
</style>
