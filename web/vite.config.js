import { defineConfig } from 'vite';
import { svelte } from '@sveltejs/vite-plugin-svelte';
import { createReadStream, existsSync, cpSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { join, resolve, normalize } from 'node:path';

// The target photos live in the Mac app's catalogue (40 MB); rather than a
// second copy in web/, they're served from there in development and copied
// into the build. /catalog/photos/… are Wikipedia photos, /catalog/sky/… the
// sky-survey thumbnails used where there's no photo. See src/lib/images.js.
const catalog = fileURLToPath(new URL('../SkyBother/Catalog', import.meta.url));
const folders = { photos: 'Images', sky: 'SkyThumbnails' };
// Single files: Sky View's whole-sky map.
const files = { 'starmap.jpg': 'StarMap.jpg' };

function catalogImages() {
  let outDir;
  return {
    name: 'sky-bother-catalog-images',
    configResolved(config) {
      outDir = resolve(config.root, config.build.outDir);
    },
    configureServer(server) {
      server.middlewares.use('/catalog', (request, response, next) => {
        const [, folder, file] = request.url.split('?')[0].split('/');
        if (files[folder] && !file) {
          response.setHeader('Content-Type', 'image/jpeg');
          return createReadStream(join(catalog, files[folder])).pipe(response);
        }
        const directory = folders[folder];
        const path = directory && file && normalize(join(catalog, directory, decodeURIComponent(file)));
        if (!path || !path.startsWith(join(catalog, directory)) || !existsSync(path)) return next();
        response.setHeader('Content-Type', 'image/jpeg');
        response.setHeader('Cache-Control', 'public, max-age=86400');
        createReadStream(path).pipe(response);
      });
    },
    closeBundle() {
      for (const [name, directory] of Object.entries(folders)) {
        cpSync(join(catalog, directory), join(outDir, 'catalog', name), { recursive: true });
      }
      for (const [name, file] of Object.entries(files)) cpSync(join(catalog, file), join(outDir, 'catalog', name));
    },
  };
}

export default defineConfig({
  plugins: [svelte(), catalogImages()],
  worker: { format: 'es' },
  // The image manifests are imported from the Mac app's catalogue.
  // /api/ is the Worker (web/worker); run `npx wrangler dev --port 8787` from
  // the repo root alongside this to use sync in development.
  server: { fs: { allow: ['..'] }, proxy: { '/api': 'http://localhost:8787' } },
});
