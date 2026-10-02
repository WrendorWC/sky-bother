import { mount } from 'svelte';
import App from './App.svelte';
import './app.css';

// Any error nothing else caught, shown on the page: on a phone there's no
// console to look in, and a silent failure just looks like nothing happening.
function showError(message) {
  let box = document.getElementById('fatal');
  if (!box) {
    box = document.createElement('p');
    box.id = 'fatal';
    box.style.cssText = 'position:fixed;left:12px;right:12px;bottom:12px;z-index:99;margin:0;padding:10px 14px;' +
      'border-radius:10px;background:#3a1518;color:#ffb4ae;border:1px solid #d95c57;font:14px/1.4 system-ui,sans-serif';
    box.onclick = () => box.remove();
    document.body.append(box);
  }
  box.textContent = `Something went wrong: ${message} (tap to dismiss)`;
}
// ResizeObserver's loop notice is the browser being chatty, not a failure.
addEventListener('error', event => {
  if (/ResizeObserver loop/.test(event.message ?? '')) return;
  showError(event.message || String(event.error));
});
addEventListener('unhandledrejection', event => showError(event.reason?.message ?? String(event.reason)));

mount(App, { target: document.getElementById('app') });

// Offline support (src/sw-template.js), on the real site only: in
// development it would serve stale files.
if ('serviceWorker' in navigator && import.meta.env.PROD) {
  addEventListener('load', () => navigator.serviceWorker.register('/sw.js').catch(() => {}));
}
