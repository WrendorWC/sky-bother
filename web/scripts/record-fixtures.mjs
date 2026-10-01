// Records live Open-Meteo forecasts for a spread of public sites into
// web/fixtures/*.request.json, for the parity check. Re-run to refresh.
//   node web/scripts/record-fixtures.mjs
import { readFileSync, writeFileSync, copyFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { homedir } from 'node:os';

const fixtures = join(dirname(fileURLToPath(import.meta.url)), '..', 'fixtures');

// Mirrors OpenMeteoClient.forecastURL; days = forecastNights + 1.
const hourly = ['cloud_cover', 'cloud_cover_low', 'cloud_cover_mid', 'cloud_cover_high', 'temperature_2m', 'dew_point_2m',
  'relative_humidity_2m', 'wind_speed_10m', 'wind_gusts_10m', 'visibility', 'precipitation_probability', 'wind_direction_10m'];
const forecastURL = (lat, lon, days) => `https://api.open-meteo.com/v1/forecast?latitude=${lat.toFixed(4)}&longitude=${lon.toFixed(4)}` +
  `&hourly=${hourly.join(',')}&timeformat=unixtime&timezone=UTC&wind_speed_unit=kmh&temperature_unit=celsius` +
  `&forecast_days=${days}&models=best_match,ncep_nbm_conus`;

const sites = [
  { file: 'kitt-peak', n: 1, name: 'Kitt Peak, Arizona', latitude: 31.9583, longitude: -111.5967, elevationMeters: 2096, bortleClass: 2, timeZoneIdentifier: 'America/Phoenix' },
  { file: 'namibia', n: 2, name: 'Hakos, Namibia', latitude: -23.2361, longitude: 16.3617, elevationMeters: 1843, bortleClass: 1, timeZoneIdentifier: 'Africa/Windhoek' },
  { file: 'tromso', n: 3, name: 'Tromsø, Norway', latitude: 69.6492, longitude: 18.9553, elevationMeters: 10, bortleClass: 4, timeZoneIdentifier: 'Europe/Oslo' },
  // Australian daylight saving starts on the first Sunday of October.
  { file: 'sydney', n: 4, name: 'Sydney, Australia', latitude: -33.8688, longitude: 151.2093, elevationMeters: 40, bortleClass: 8, timeZoneIdentifier: 'Australia/Sydney' },
];

const rig = { apertureMillimeters: 50, focalLengthMillimeters: 250, hasNarrowbandFilter: false, id: '00000000-0000-0000-0000-000000000001',
  mountType: 'altAzimuth', name: 'ZWO Seestar S50', pixelSizeMicrons: 2.9, sensorHeightMillimeters: 11.14, sensorWidthMillimeters: 6.26, supportsMosaic: true, zenithAvoidanceAltitude: 80 };
const preferences = { autoFitsText: true, forecastNights: 7, includeComets: true, includeOversizedTargets: true, includeStarClusters: true,
  includeStars: true, integrationGoalMinutes: 180, maximumCloudCover: 30, minimumDarkness: 0.5, minimumScore: 15, minimumUsefulAltitude: 30,
  nightMode: false, planEmphasis: 'longerIntegration', showsClouds: true, showsZenithRiskWarnings: true, textScale: 1, usesImperialUnits: false };

const comets = join(homedir(), 'Library', 'Application Support', 'SkyBother', 'CometEls.txt');
if (existsSync(comets)) copyFileSync(comets, join(fixtures, 'CometEls.txt'));

const now = new Date(); now.setUTCMinutes(0, 0, 0);
for (const { file, n, ...site } of sites) {
  const response = await fetch(forecastURL(site.latitude, site.longitude, preferences.forecastNights + 1));
  if (!response.ok) throw new Error(`${file}: HTTP ${response.status}`);
  const request = {
    site: { id: `00000000-0000-0000-0001-00000000000${n}`, horizonAltitude: 20, ...site },
    rig, preferences, customTargets: [],
    openMeteoResponse: await response.text(),
    cometElementsFile: 'CometEls.txt',
    now: now.toISOString().replace('.000', ''),
  };
  writeFileSync(join(fixtures, `${file}.request.json`), JSON.stringify(request));
  console.log(`recorded ${file}`);
}
