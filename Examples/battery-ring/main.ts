import { loom } from '@loom/core';
import { w } from '@loom/widget';

export default loom(async () => {
  // Loom.device is a property bag, not a set of methods — a snapshot taken when the run started.
  // There is nothing to await and nothing to call.
  const level = Loom.device.batteryLevel;

  if (level === null) {
    Loom.log.warn('Battery level unavailable — simulators usually report null.');
  }

  return {
    percent: level === null ? null : Math.round(level * 100),
    charging: Loom.device.isCharging,
    model: Loom.device.model,
    system: Loom.device.systemVersion,
  };
}, {
  name: 'Battery Ring',
  description: 'Shows the current battery level as a ring on the home screen.',
  widget: {
    // How long WidgetKit should wait before asking for fresh data, in seconds. iOS treats this as
    // a hint and applies its own budget — you will not get a refresh every 15 minutes forever.
    refreshAfter: 900,
  },
});

// The widget export runs immediately after the handler above resolves, in the same context, with
// whatever the handler returned available as ctx.data. It can be async and can call the bridge.
export const widget = (ctx) => {
  const data = ctx.data ?? {};
  const known = typeof data.percent === 'number';
  const percent = known ? data.percent : 0;

  const color = data.charging ? 'teal'
    : percent <= 20 ? 'red'
    : percent <= 50 ? 'yellow'
    : 'green';

  // Returning a single node uses it for every widget size. Return a { small, medium, large,
  // extraLarge } object instead when the layouts should differ — see Weather Brief.
  return w.vstack([
    w.ring({
      value: percent,
      total: 100,
      color,
      label: known ? `${percent}%` : '—',
      caption: data.charging ? 'Charging' : 'Battery',
    }),
    w.hstack([
      w.icon(data.charging ? 'bolt.fill' : 'iphone', { size: 10, color }),
      w.text(data.model ?? 'iPhone', { font: 'caption', color: 'secondary' }),
    ], { spacing: 4 }),
  ], { spacing: 8, padding: 12 });
};
