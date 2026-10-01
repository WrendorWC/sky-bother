// A setup link carries a site, rig, preferences and custom targets in the
// address itself — https://skybother.com/#setup=… — so another device (or a
// friend) can take on the same setup in one tap. The Mac app makes the same
// links (StoredSettings.webSetupLink in Support/Persistence.swift): the
// payload is base64url of the JSON { v: 1, site, rig, preferences,
// customTargets }, in the shapes settings.json uses.

const prefix = '#setup=';

export function setupLink(settings) {
  const { site, rig, preferences, customTargets = [] } = settings;
  const json = JSON.stringify({ v: 1, site, rig, preferences, customTargets });
  const bytes = new TextEncoder().encode(json);
  let binary = '';
  bytes.forEach(b => (binary += String.fromCharCode(b)));
  const encoded = btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  return `${location.origin}/${prefix}${encoded}`;
}

export const isSetupHash = hash => hash.startsWith(prefix);

/** The settings in a #setup= hash; throws if it isn't one Sky Bother made. */
export function readSetup(hash) {
  const encoded = hash.slice(prefix.length).replace(/-/g, '+').replace(/_/g, '/');
  const binary = atob(encoded + '='.repeat((4 - (encoded.length % 4)) % 4));
  const json = new TextDecoder().decode(Uint8Array.from(binary, c => c.charCodeAt(0)));
  const setup = JSON.parse(json);
  if (setup.v !== 1 || !setup.site || !setup.rig || !setup.preferences) throw new Error('not a Sky Bother setup');
  return { site: setup.site, rig: setup.rig, preferences: setup.preferences, customTargets: setup.customTargets ?? [] };
}
