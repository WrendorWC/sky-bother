// Runs engine.wasm — the Mac app's own planner, compiled from the same Swift —
// off the main thread. Strings cross as UTF-8; see engine/Sources/engine-wasm.
import { WASI, File, OpenFile, ConsoleStdout } from '@bjorn3/browser_wasi_shim';

const ready = (async () => {
  const wasi = new WASI([], [], [
    new OpenFile(new File([])),
    ConsoleStdout.lineBuffered(line => console.log('[engine]', line)),
    ConsoleStdout.lineBuffered(line => console.warn('[engine]', line)),
  ]);
  const [{ instance }, catalog] = await Promise.all([
    WebAssembly.instantiateStreaming(fetch('/engine.wasm'), { wasi_snapshot_preview1: wasi.wasiImport }),
    fetch('/catalog-extended.json').then(r => r.text()),
  ]);
  wasi.initialize(instance);
  const engine = instance.exports;
  call(engine, engine.sb_load_catalog, catalog);
  return engine;
})();

function call(engine, fn, text) {
  const bytes = new TextEncoder().encode(text);
  const pointer = engine.sb_alloc(bytes.length);
  new Uint8Array(engine.memory.buffer, pointer, bytes.length).set(bytes);
  const result = fn(pointer, bytes.length);
  engine.sb_free(pointer);
  return result;
}

function readResult(engine, pointer) {
  return JSON.parse(new TextDecoder().decode(new Uint8Array(engine.memory.buffer, pointer, engine.sb_result_length())));
}

self.onmessage = async ({ data: { id, kind, request } }) => {
  try {
    const engine = await ready;
    let result;
    if (kind === 'defaults') {
      result = readResult(engine, engine.sb_defaults());
    } else if (kind === 'planNights') {
      const started = performance.now();
      result = readResult(engine, call(engine, engine.sb_plan_nights, JSON.stringify(request)));
      if (result.error) throw new Error(result.error);
      console.debug(`[engine] planned ${result.length} nights in ${Math.round(performance.now() - started)} ms`);
    } else if (kind === 'targetDetail') {
      result = readResult(engine, call(engine, engine.sb_target_detail, JSON.stringify(request)));
      if (result.error) throw new Error(result.error);
    }
    self.postMessage({ id, result });
  } catch (error) {
    self.postMessage({ id, error: String(error?.message ?? error) });
  }
};
