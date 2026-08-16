import { loom } from '@loom/core';
import { w } from '@loom/widget';

const CACHE = 'forecast';
const MAX_AGE = 20 * 60 * 1000;

// WMO weather codes, grouped. Open-Meteo returns one of these on `current.weather_code`.
const CONDITIONS = [
  { codes: [0], label: 'Clear', icon: 'sun.max.fill', tint: ['orange', 'yellow'] },
  { codes: [1, 2], label: 'Partly cloudy', icon: 'cloud.sun.fill', tint: ['blue', 'teal'] },
  { codes: [3], label: 'Overcast', icon: 'cloud.fill', tint: ['indigo', 'blue'] },
  { codes: [45, 48], label: 'Fog', icon: 'cloud.fog.fill', tint: ['secondary', 'blue'] },
  { codes: [51, 53, 55, 56, 57], label: 'Drizzle', icon: 'cloud.drizzle.fill', tint: ['teal', 'blue'] },
  { codes: [61, 63, 65, 66, 67], label: 'Rain', icon: 'cloud.rain.fill', tint: ['blue', 'indigo'] },
  { codes: [71, 73, 75, 77], label: 'Snow', icon: 'cloud.snow.fill', tint: ['teal', 'white'] },
  { codes: [80, 81, 82], label: 'Showers', icon: 'cloud.heavyrain.fill', tint: ['blue', 'indigo'] },
  { codes: [85, 86], label: 'Snow showers', icon: 'cloud.snow.fill', tint: ['teal', 'indigo'] },
  { codes: [95, 96, 99], label: 'Thunderstorms', icon: 'cloud.bolt.rain.fill', tint: ['purple', 'indigo'] },
];

export default loom(async (ctx) => {
  const cached = Loom.kv.get(CACHE);
  const age = cached ? Date.now() - cached.at : Infinity;

  // A manual run always refetches — you tapped it because you want the current number. Every
  // other trigger is happy with a recent answer, which keeps background runs cheap.
  if (age < MAX_AGE && ctx.trigger !== 'manual') {
    Loom.log.debug('Serving cached forecast', { minutesOld: Math.round(age / 60000) });
    return cached.data;
  }

  // Prompts for location on first use, resolves a single fix at ~100m accuracy.
  const here = await Loom.location.current();

  const url = 'https://api.open-meteo.com/v1/forecast'
    + `?latitude=${here.lat.toFixed(3)}&longitude=${here.lng.toFixed(3)}`
    + '&current=temperature_2m,apparent_temperature,weather_code'
    + '&hourly=temperature_2m&forecast_days=2&timezone=auto';

  const res = await Loom.network.fetch(url);
  if (!res.ok) throw new Error(`Open-Meteo returned ${res.status}`);
  const body = JSON.parse(res._body);

  const condition = CONDITIONS.find((c) => c.codes.includes(body.current.weather_code))
    ?? { label: 'Unknown', icon: 'questionmark.circle', tint: ['secondary', 'primary'] };

  const data = {
    temperature: Math.round(body.current.temperature_2m),
    feelsLike: Math.round(body.current.apparent_temperature),
    label: condition.label,
    icon: condition.icon,
    tint: condition.tint,
    hourly: nextHours(body, 12),
  };

  Loom.kv.set(CACHE, { at: Date.now(), data });
  Loom.log.info('Forecast updated', { temperature: data.temperature, condition: data.label });
  return data;
}, {
  name: 'Weather Brief',
  description: 'Current conditions and the next twelve hours for wherever you are.',
  permissions: ['location'],
  triggers: { backgroundRefresh: true },
  widget: { refreshAfter: 1800 },
});

// ISO timestamps sort lexically, so finding "now" in the hourly series is a string comparison.
function nextHours(body, count: number) {
  const times: string[] = body.hourly.time;
  const start = Math.max(0, times.findIndex((t) => t >= body.current.time));
  return times.slice(start, start + count).map((t, i) => ({
    label: t.slice(11, 13),
    value: Math.round(body.hourly.temperature_2m[start + i]),
  }));
}

export const widget = (ctx) => {
  const d = ctx.data;
  if (!d || typeof d.temperature !== 'number') {
    return w.vstack([
      w.icon('cloud.fill', { size: 22, color: 'secondary' }),
      w.text('Run once to load the forecast.', { font: 'caption', color: 'secondary', lineLimit: 3 }),
    ], { spacing: 6, padding: 14 });
  }

  // Different layouts per size. The keys are optional — omit one and that size renders nothing,
  // so cover every size you expect people to add.
  return { small: small(d), medium: medium(d), large: large(d), extraLarge: large(d) };
};

// w.gradient is not renderable on its own — it is only ever a value for a `background` prop.
const backdrop = (d) => w.gradient({ colors: d.tint, direction: 'diagonal' });

function small(d) {
  return w.vstack([
    w.icon(d.icon, { size: 26, color: 'white' }),
    w.text(`${d.temperature}°`, { font: 'largeTitle', bold: true, color: 'white' }),
    w.text(d.label, { font: 'caption', color: 'white', lineLimit: 1 }),
  ], { spacing: 2, padding: 12, background: backdrop(d) });
}

function medium(d) {
  return w.hstack([
    w.vstack([
      w.icon(d.icon, { size: 24, color: 'white' }),
      w.text(`${d.temperature}°`, { font: 'title', bold: true, color: 'white' }),
      w.text(`Feels ${d.feelsLike}°`, { font: 'caption2', color: 'white' }),
    ], { spacing: 2, alignment: 'leading' }),
    w.spacer(),
    w.sparkline({ data: d.hourly, color: 'white' }),
  ], { spacing: 12, padding: 14, background: backdrop(d) });
}

function large(d) {
  return w.vstack([
    w.hstack([
      w.icon(d.icon, { size: 28, color: 'white' }),
      w.vstack([
        w.text(`${d.temperature}°`, { font: 'largeTitle', bold: true, color: 'white' }),
        w.text(`${d.label} · feels ${d.feelsLike}°`, { font: 'caption', color: 'white', lineLimit: 1 }),
      ], { spacing: 0, alignment: 'leading' }),
      w.spacer(),
    ], { spacing: 10 }),
    w.divider({ color: 'white' }),
    w.lineChart({ data: d.hourly, color: 'white', smooth: true }),
  ], { spacing: 10, padding: 16, background: backdrop(d) });
}
