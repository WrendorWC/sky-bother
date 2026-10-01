// Mac/web parity check: runs every request in web/fixtures (and fixtures/local)
// through the native engine-cli and through engine.wasm, and diffs the JSON.
// Structure, text, order and dates must match exactly; numbers to 1e-9. They
// can't match to the bit: Apple's libm and wasi-libc round the last bit of
// sin/cos/atan2 differently, which shows up around 1e-14 on a 0–100 score.
//   node web/scripts/parity.mjs
import { execFileSync } from 'node:child_process';
import { readFileSync, readdirSync, existsSync, writeFileSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { WASI } from 'node:wasi';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const web = join(dirname(fileURLToPath(import.meta.url)), '..');
const catalogPath = join(web, '..', 'SkyBother', 'Catalog', 'ExtendedCatalog.json');
const cli = join(web, 'engine', '.build', 'debug', 'engine-cli');
const wasmPath = process.argv[2] ?? join(web, 'public', 'engine.wasm');

const wasi = new WASI({ version: 'preview1', args: [], env: {} });
const { instance } = await WebAssembly.instantiate(readFileSync(wasmPath), { wasi_snapshot_preview1: wasi.wasiImport });
wasi.initialize(instance);
const e = instance.exports;

function call(fn, text) {
  const bytes = new TextEncoder().encode(text);
  const ptr = e.sb_alloc(bytes.length);
  new Uint8Array(e.memory.buffer, ptr, bytes.length).set(bytes);
  const out = fn(ptr, bytes.length);
  e.sb_free(ptr);
  return out;
}
call(e.sb_load_catalog, readFileSync(catalogPath, 'utf8'));

const requests = [];
for (const dir of [join(web, 'fixtures'), join(web, 'fixtures', 'local')]) {
  if (!existsSync(dir)) continue;
  for (const f of readdirSync(dir).filter(f => f.endsWith('.request.json'))) requests.push(join(dir, f));
}

const numericGaps = [];
function compare(a, b, path, out) {
  if (typeof a === 'number' && typeof b === 'number') {
    const gap = Math.abs(a - b);
    numericGaps.push(gap);
    if (gap > 1e-9 * Math.max(1, Math.abs(a))) out.push(`${path}: ${a} vs ${b}`);
  } else if (Array.isArray(a) && Array.isArray(b)) {
    if (a.length !== b.length) out.push(`${path}: ${a.length} items vs ${b.length}`);
    else a.forEach((x, i) => compare(x, b[i], `${path}[${i}]`, out));
  } else if (a && b && typeof a === 'object' && typeof b === 'object') {
    for (const k of new Set([...Object.keys(a), ...Object.keys(b)])) compare(a[k], b[k], `${path}.${k}`, out);
  } else if (a !== b) out.push(`${path}: ${JSON.stringify(a)} vs ${JSON.stringify(b)}`);
}

let failures = 0;
const scratch = mkdtempSync(join(tmpdir(), 'skybother-parity-'));
for (const path of requests) {
  // Fixtures name a shared comet file rather than each carrying 160 KB of it.
  const request = JSON.parse(readFileSync(path, 'utf8'));
  if (request.cometElementsFile) {
    request.cometElements = readFileSync(join(dirname(path), request.cometElementsFile), 'utf8');
    delete request.cometElementsFile;
  }
  const text = JSON.stringify(request);
  const inlined = join(scratch, 'request.json');
  writeFileSync(inlined, text);
  const native = execFileSync(cli, [catalogPath, inlined], { maxBuffer: 1 << 28 }).toString();
  const t0 = performance.now();
  const ptr = call(e.sb_plan_nights, text);
  const ms = performance.now() - t0;
  const wasm = new TextDecoder().decode(new Uint8Array(e.memory.buffer, ptr, e.sb_result_length()));
  const nights = JSON.parse(wasm);
  const name = path.slice(web.length + 1);
  if (nights.error) { console.log(`✗ ${name}: wasm error ${nights.error}`); failures++; continue; }
  const differences = [];
  compare(JSON.parse(native), nights, '', differences);
  const worst = Math.max(0, ...numericGaps);
  numericGaps.length = 0;
  if (differences.length === 0) {
    console.log(`✓ ${name}: ${nights.length} nights match (largest numeric gap ${worst.toExponential(1)}; ${ms.toFixed(0)} ms in wasm)`);
    console.log(`    scores ${nights.map(n => `${n.planKey} ${n.score.toFixed(1)}`).join(' · ')}`);
  } else {
    failures++;
    console.log(`✗ ${name}: ${differences.length} differences`);
    for (const d of differences.slice(0, 20)) console.log(`    ${d}`);
  }
}
process.exit(failures ? 1 : 0);
