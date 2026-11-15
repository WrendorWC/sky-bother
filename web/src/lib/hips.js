// A cutout of the colour Digitized Sky Survey, drawn here from the survey's
// HiPS tiles rather than asked of a server that renders cutouts (CDS's
// hips2fits, which went down with the rest of CDS in November 2026 and left
// every framing preview blank). Tiles are plain JPEGs any mirror can serve,
// so this needs nothing but a copy of the survey.
//
// A HiPS survey is the sky cut into HEALPix cells: at order k there are
// 12·4^k tiles, each 512×512 pixels of order k+9. To draw a gnomonic (TAN)
// picture we walk its pixels, find the sky position each one looks at, find
// which tile and which pixel of it holds that position, and sample there.
//
// The mirrors, in order of preference. IRSA (NASA/Caltech) mirrors CDS's
// survey byte for byte and lets other sites read it; CDS's own copy is kept
// as the fallback for when it's back.
export const SURVEYS = [
  'https://irsa.ipac.caltech.edu/data/hips/CDS/DSS2/color',
  'https://alasky.cds.unistra.fr/DSS/DSSColor',
];

const TILE = 512;          // pixels across a tile
const TILE_BITS = 9;       // log2(TILE)
const MAX_ORDER = 9;       // deepest tiles the survey has
const ORDER9_PIXEL = 2.236e-4; // degrees per pixel at the deepest tiles

// The tile order whose pixels are about the size of the picture's: finer
// would fetch detail that's thrown away, coarser would blur it.
export function orderFor(degreesPerPixel) {
  const k = MAX_ORDER - Math.round(Math.log2(degreesPerPixel / ORDER9_PIXEL));
  return Math.max(0, Math.min(MAX_ORDER, k));
}

// HEALPix: a sky position to (face, x, y) at nside, x and y continuous in
// [0, nside) within the face. The standard ang2pix, kept fractional so that
// pixels can be interpolated.
export function toFace(raDeg, decDeg, nside) {
  const z = Math.sin(decDeg * Math.PI / 180);
  const za = Math.abs(z);
  let tt = ((raDeg % 360) + 360) % 360 / 90; // [0, 4)
  if (tt >= 4) tt = 0;
  if (za <= 2 / 3) {
    const t1 = nside * (0.5 + tt), t2 = nside * z * 0.75;
    const jp = t1 - t2, jm = t1 + t2;
    const ifp = Math.floor(jp / nside), ifm = Math.floor(jm / nside);
    const face = ifp === ifm ? (ifp % 4) + 4 : ifp < ifm ? ifp % 4 : (ifm % 4) + 8;
    return { face, x: jm - Math.floor(jm / nside) * nside, y: nside - (jp - Math.floor(jp / nside) * nside) };
  }
  const ntt = Math.min(3, Math.floor(tt));
  const tp = tt - ntt;
  const tmp = nside * Math.sqrt(3 * (1 - za));
  const jp = Math.min(nside, tp * tmp), jm = Math.min(nside, (1 - tp) * tmp);
  return z > 0 ? { face: ntt, x: nside - jm, y: nside - jp } : { face: ntt + 8, x: jp, y: jm };
}

// Interleaves the bits of x (even places) and y (odd places): HEALPix's
// nested numbering within a face.
function interleave(x, y) {
  let n = 0;
  for (let b = 0; b < 30; b++) n += (((x >> b) & 1) + 2 * ((y >> b) & 1)) * 2 ** (2 * b);
  return n;
}

export function tilePath(order, npix) {
  return `Norder${order}/Dir${Math.floor(npix / 10000) * 10000}/Npix${npix}.jpg`;
}

// Where a position falls: which tile, and where in that tile's image
// (column, row from the top), fractional.
export function locate(raDeg, decDeg, order) {
  const nside = 2 ** (order + TILE_BITS);
  let { face, x, y } = toFace(raDeg, decDeg, nside);
  x = Math.min(nside - 1e-6, Math.max(0, x));
  y = Math.min(nside - 1e-6, Math.max(0, y));
  const tx = Math.floor(x / TILE), ty = Math.floor(y / TILE);
  const npix = face * 4 ** order + interleave(tx, ty);
  const lx = x - tx * TILE, ly = y - ty * TILE;
  // In a HiPS tile image, x runs down the rows and y along the columns
  // (checked against NASA SkyView pictures of the same fields).
  return { npix, column: ly, row: lx };
}

// The sky position each pixel of a gnomonic picture looks at: centre
// (ra, dec), `fov` degrees along the longer side, north up and east left.
function* positions(ra, dec, fov, width, height) {
  const d2r = Math.PI / 180;
  const a0 = ra * d2r, d0 = dec * d2r;
  const sinD0 = Math.sin(d0), cosD0 = Math.cos(d0);
  // Tangent-plane units per pixel, so the longer side spans `fov`.
  const half = Math.tan(fov * d2r / 2);
  const scale = 2 * half / Math.max(width, height);
  for (let j = 0; j < height; j++) {
    const eta = ((height - 1) / 2 - j) * scale;
    for (let i = 0; i < width; i++) {
      const xi = ((width - 1) / 2 - i) * scale; // east is left
      const den = cosD0 - eta * sinD0;
      const a = a0 + Math.atan2(xi, den);
      const d = Math.atan2(sinD0 + eta * cosD0, Math.hypot(xi, den));
      yield [a / d2r, d / d2r];
    }
  }
}

// Renders a cutout into an RGBA array (width·height·4). `getTile(order,
// npix)` returns a promise of the tile's RGBA pixels (TILE·TILE·4), or null
// when it can't be had; the picture is black there.
export async function renderCutout({ ra, dec, fov, width, height, getTile }) {
  const order = orderFor(fov / Math.max(width, height));
  // Where every pixel lands, and so which tiles are needed.
  const spots = new Array(width * height);
  const needed = new Set();
  let p = 0;
  for (const [a, d] of positions(ra, dec, fov, width, height)) {
    const spot = locate(a, d, order);
    spots[p++] = spot;
    needed.add(spot.npix);
  }
  const tiles = new Map();
  await Promise.all([...needed].map(async npix => tiles.set(npix, await getTile(order, npix))));

  const out = new Uint8ClampedArray(width * height * 4);
  for (let i = 0; i < spots.length; i++) {
    const { npix, column, row } = spots[i];
    const tile = tiles.get(npix);
    const o = i * 4;
    out[o + 3] = 255;
    if (!tile) continue;
    // Bilinear within the tile; at its edge, the edge pixel.
    const cx = Math.min(TILE - 1, Math.max(0, column - 0.5)), cy = Math.min(TILE - 1, Math.max(0, row - 0.5));
    const x0 = Math.floor(cx), y0 = Math.floor(cy);
    const x1 = Math.min(TILE - 1, x0 + 1), y1 = Math.min(TILE - 1, y0 + 1);
    const fx = cx - x0, fy = cy - y0;
    const i00 = (y0 * TILE + x0) * 4, i10 = (y0 * TILE + x1) * 4, i01 = (y1 * TILE + x0) * 4, i11 = (y1 * TILE + x1) * 4;
    for (let c = 0; c < 3; c++) {
      const top = tile[i00 + c] * (1 - fx) + tile[i10 + c] * fx;
      const bottom = tile[i01 + c] * (1 - fx) + tile[i11 + c] * fx;
      out[o + c] = top * (1 - fy) + bottom * fy;
    }
  }
  return out;
}
