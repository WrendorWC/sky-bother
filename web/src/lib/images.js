// A target's picture, as TargetThumbnail picks it on the Mac: a Wikipedia
// photo if there is one, else a Digitized Sky Survey thumbnail, else nothing
// (a placeholder sky). The files are served by the catalogue plugin in
// vite.config.js.
import photos from '../../../SkyBother/Catalog/TargetImages.json';
import skyThumbnails from '../../../SkyBother/Catalog/SkyThumbnails.json';

export function targetImage(designation) {
  const photo = photos[designation];
  if (photo) {
    return {
      url: `/catalog/photos/${encodeURIComponent(photo.file)}`,
      credit: `Photo: ${photo.sourceTitle ?? designation} via Wikipedia`,
      sourceURL: photo.sourceURL,
    };
  }
  const sky = skyThumbnails[designation];
  if (sky) {
    return {
      url: `/catalog/sky/${encodeURIComponent(sky.file)}`,
      credit: 'Digitized Sky Survey (STScI/NASA), colour by CDS',
      sourceURL: null,
    };
  }
  return null;
}
