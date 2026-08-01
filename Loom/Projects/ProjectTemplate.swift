import Foundation

struct ProjectTemplate: Identifiable {
    let id: String
    let displayName: String
    let tagline: String
    let icon: String
    let requiresM4: Bool
    let defaultName: String
    let mainTS: String
    let widgetTS: String
}

// MARK: - Built-in Templates

extension ProjectTemplate {
    static let all: [ProjectTemplate] = [weather, crypto, news, habits, aiQuote, battery]

    // MARK: Weather

    static let weather = ProjectTemplate(
        id: "weather",
        displayName: "Weather",
        tagline: "Live conditions via Open-Meteo",
        icon: "cloud.sun.fill",
        requiresM4: false,
        defaultName: "Weather",
        mainTS: """
import { loom } from '@loom/core';

export default loom(async (ctx) => {
  // Open-Meteo — free weather API, no key required.
  // Change latitude/longitude to your city.
  const url = 'https://api.open-meteo.com/v1/forecast'
    + '?latitude=51.5074&longitude=-0.1278'
    + '&current_weather=true';

  const resp = await Loom.network.fetch(url);
  const data = JSON.parse(resp.body);
  const cw = data.current_weather;

  return {
    temp: Math.round(cw.temperature),
    windspeed: Math.round(cw.windspeed),
    code: cw.weathercode,
    unit: '°C',
    city: 'London',
  };
}, {
  name: 'Weather',
  description: 'Current weather from Open-Meteo.',
  triggers: { schedule: '*/30 * * * *' },
});
""",
        widgetTS: """
import { w } from '@loom/widget';

function icon(code) {
  if (code === 0)  return 'sun.max.fill';
  if (code <= 3)   return 'cloud.sun.fill';
  if (code <= 48)  return 'cloud.fog.fill';
  if (code <= 67)  return 'cloud.rain.fill';
  if (code <= 77)  return 'snowflake';
  if (code <= 82)  return 'cloud.drizzle.fill';
  if (code <= 99)  return 'cloud.bolt.rain.fill';
  return 'questionmark';
}

function desc(code) {
  if (code === 0) return 'Clear sky';
  if (code <= 3)  return 'Partly cloudy';
  if (code <= 48) return 'Foggy';
  if (code <= 55) return 'Drizzle';
  if (code <= 65) return 'Rain';
  if (code <= 77) return 'Snow';
  if (code <= 82) return 'Showers';
  return 'Thunderstorm';
}

export const small = (ctx) => {
  const d = ctx.input || {};
  return w.vstack([
    w.icon(icon(d.code || 0), { size: 30, color: 'accent' }),
    w.text((d.temp != null ? d.temp : '--') + (d.unit || '°C'), { font: 'title', color: 'primary' }),
    w.text(d.city || 'Weather', { font: 'caption2', color: 'secondary' }),
  ], { alignment: 'center' });
};

export const medium = (ctx) => {
  const d = ctx.input || {};
  return w.hstack([
    w.vstack([
      w.icon(icon(d.code || 0), { size: 44, color: 'accent' }),
      w.text((d.temp != null ? d.temp : '--') + (d.unit || '°C'), { font: 'largeTitle' }),
    ], { alignment: 'center' }),
    w.spacer(),
    w.vstack([
      w.text(d.city || 'Weather', { font: 'headline' }),
      w.text(desc(d.code || 0), { font: 'subheadline', color: 'secondary' }),
      w.spacer(),
      w.hstack([
        w.icon('wind', { size: 12, color: 'secondary' }),
        w.text(' ' + (d.windspeed || '--') + ' km/h', { font: 'caption', color: 'secondary' }),
      ]),
    ], { alignment: 'leading' }),
  ]);
};

export const large = (ctx) => {
  const d = ctx.input || {};
  return w.vstack([
    w.hstack([
      w.text(d.city || 'Weather', { font: 'headline' }),
      w.spacer(),
      w.icon('location.fill', { size: 12, color: 'secondary' }),
    ]),
    w.spacer(),
    w.icon(icon(d.code || 0), { size: 64, color: 'accent' }),
    w.text((d.temp != null ? d.temp : '--') + (d.unit || '°C'), { font: 'largeTitle' }),
    w.text(desc(d.code || 0), { font: 'title3', color: 'secondary' }),
    w.spacer(),
    w.divider(),
    w.hstack([
      w.icon('wind', { size: 14, color: 'secondary' }),
      w.text(' ' + (d.windspeed || '--') + ' km/h', { font: 'footnote', color: 'secondary' }),
      w.spacer(),
      w.icon('thermometer.medium', { size: 14, color: 'secondary' }),
      w.text(' Feels like ' + (d.temp != null ? d.temp : '--') + (d.unit || '°C'), { font: 'footnote', color: 'secondary' }),
    ]),
  ], { alignment: 'leading' });
};
"""
    )

    // MARK: Crypto

    static let crypto = ProjectTemplate(
        id: "crypto",
        displayName: "Crypto",
        tagline: "BTC & ETH prices via CoinGecko",
        icon: "bitcoinsign.circle.fill",
        requiresM4: false,
        defaultName: "Crypto",
        mainTS: """
import { loom } from '@loom/core';

export default loom(async (ctx) => {
  // CoinGecko public API — no key required (rate limited to ~30 req/min).
  const url = 'https://api.coingecko.com/api/v3/simple/price'
    + '?ids=bitcoin,ethereum&vs_currencies=usd&include_24hr_change=true';

  const resp = await Loom.network.fetch(url);
  const data = JSON.parse(resp.body);

  const fmt = (n) => n >= 1000 ? '$' + (n / 1000).toFixed(1) + 'k' : '$' + n.toFixed(2);
  const sign = (n) => (n >= 0 ? '+' : '') + n.toFixed(2) + '%';

  return {
    btc: { price: fmt(data.bitcoin.usd), change: sign(data.bitcoin.usd_24h_change), up: data.bitcoin.usd_24h_change >= 0 },
    eth: { price: fmt(data.ethereum.usd), change: sign(data.ethereum.usd_24h_change), up: data.ethereum.usd_24h_change >= 0 },
    updated: new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }),
  };
}, {
  name: 'Crypto',
  description: 'BTC and ETH prices from CoinGecko.',
  triggers: { schedule: '*/15 * * * *' },
});
""",
        widgetTS: """
import { w } from '@loom/widget';

function coinRow(name, ticker, data) {
  return w.hstack([
    w.icon('bitcoinsign.circle.fill', { size: 20, color: 'accent' }),
    w.vstack([
      w.text(name, { font: 'caption', color: 'secondary' }),
      w.text(data ? data.price : '--', { font: 'headline' }),
    ], { alignment: 'leading' }),
    w.spacer(),
    w.text(data ? data.change : '--', { font: 'caption', color: data && data.up ? 'green' : 'red' }),
  ]);
}

export const small = (ctx) => {
  const d = ctx.input || {};
  const btc = d.btc || {};
  return w.vstack([
    w.hstack([
      w.icon('bitcoinsign.circle.fill', { size: 16, color: 'accent' }),
      w.text(' BTC', { font: 'caption', color: 'secondary' }),
    ]),
    w.text(btc.price || '--', { font: 'title2' }),
    w.text(btc.change || '--', { font: 'caption', color: btc.up ? 'green' : 'red' }),
  ], { alignment: 'center' });
};

export const medium = (ctx) => {
  const d = ctx.input || {};
  return w.vstack([
    coinRow('Bitcoin', 'BTC', d.btc),
    w.divider(),
    coinRow('Ethereum', 'ETH', d.eth),
    w.spacer(),
    w.text('Updated ' + (d.updated || '--'), { font: 'caption2', color: 'tertiary' }),
  ]);
};

export const large = (ctx) => {
  const d = ctx.input || {};
  return w.vstack([
    w.text('Crypto', { font: 'headline', color: 'secondary' }),
    w.spacer(),
    w.vstack([
      coinRow('Bitcoin', 'BTC', d.btc),
      w.spacer(),
      coinRow('Ethereum', 'ETH', d.eth),
    ]),
    w.spacer(),
    w.text('Updated ' + (d.updated || '--'), { font: 'caption2', color: 'tertiary' }),
  ], { alignment: 'leading' });
};

export const extraLarge = (ctx) => {
  const d = ctx.input || {};
  return w.hstack([
    w.vstack([
      w.text('Bitcoin', { font: 'headline' }),
      w.text(d.btc ? d.btc.price : '--', { font: 'largeTitle' }),
      w.text(d.btc ? d.btc.change : '--', { font: 'title3', color: d.btc && d.btc.up ? 'green' : 'red' }),
    ], { alignment: 'leading' }),
    w.divider(),
    w.vstack([
      w.text('Ethereum', { font: 'headline' }),
      w.text(d.eth ? d.eth.price : '--', { font: 'largeTitle' }),
      w.text(d.eth ? d.eth.change : '--', { font: 'title3', color: d.eth && d.eth.up ? 'green' : 'red' }),
    ], { alignment: 'leading' }),
  ]);
};
"""
    )

    // MARK: HN News

    static let news = ProjectTemplate(
        id: "news",
        displayName: "HN Digest",
        tagline: "Top Hacker News stories",
        icon: "newspaper.fill",
        requiresM4: false,
        defaultName: "HN Digest",
        mainTS: """
import { loom } from '@loom/core';

export default loom(async (ctx) => {
  // Hacker News Firebase API — public, no key required.
  const idsResp = await Loom.network.fetch('https://hacker-news.firebaseio.com/v0/topstories.json');
  const ids = JSON.parse(idsResp.body).slice(0, 5);

  const stories = await Promise.all(ids.map(async (id) => {
    const r = await Loom.network.fetch('https://hacker-news.firebaseio.com/v0/item/' + id + '.json');
    const s = JSON.parse(r.body);
    return { title: s.title, score: s.score, comments: s.descendants || 0, url: s.url || '' };
  }));

  return { stories, updated: new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }) };
}, {
  name: 'HN Digest',
  description: 'Top stories from Hacker News.',
  triggers: { schedule: '0 * * * *' },
});
""",
        widgetTS: """
import { w } from '@loom/widget';

function storyRow(s, showScore) {
  return w.vstack([
    w.text(s.title, { font: 'caption', lineLimit: 2 }),
    showScore ? w.hstack([
      w.icon('arrow.up', { size: 10, color: 'accent' }),
      w.text(' ' + s.score + '  ·  ' + s.comments + ' comments', { font: 'caption2', color: 'secondary' }),
    ]) : w.spacer(),
  ], { alignment: 'leading' });
}

export const small = (ctx) => {
  const d = ctx.input || {};
  const top = (d.stories || [])[0] || {};
  return w.vstack([
    w.hstack([
      w.icon('newspaper.fill', { size: 12, color: 'accent' }),
      w.text(' Top Story', { font: 'caption2', color: 'secondary' }),
    ]),
    w.spacer(),
    w.text(top.title || 'No stories yet', { font: 'caption', lineLimit: 4 }),
  ], { alignment: 'leading' });
};

export const medium = (ctx) => {
  const d = ctx.input || {};
  const stories = (d.stories || []).slice(0, 3);
  return w.vstack([
    w.hstack([
      w.icon('newspaper.fill', { size: 12, color: 'accent' }),
      w.text(' Hacker News', { font: 'caption', color: 'secondary' }),
    ]),
    w.divider(),
    ...stories.map((s) => storyRow(s, false)),
  ], { alignment: 'leading' });
};

export const large = (ctx) => {
  const d = ctx.input || {};
  const stories = (d.stories || []).slice(0, 5);
  return w.vstack([
    w.hstack([
      w.icon('newspaper.fill', { size: 14, color: 'accent' }),
      w.text(' Hacker News', { font: 'subheadline' }),
      w.spacer(),
      w.text(d.updated || '', { font: 'caption2', color: 'tertiary' }),
    ]),
    w.divider(),
    ...stories.map((s) => storyRow(s, true)),
  ], { alignment: 'leading' });
};
"""
    )

    // MARK: Habits

    static let habits = ProjectTemplate(
        id: "habits",
        displayName: "Habits",
        tagline: "Daily counter with interactive button",
        icon: "checkmark.circle.fill",
        requiresM4: false,
        defaultName: "Habits",
        mainTS: """
import { loom } from '@loom/core';

// Reads the tap timestamp written by the widget button (Loom.kv key: 'tap')
// and increments the daily counter accordingly.
export default loom(async (ctx) => {
  const todayKey = new Date().toISOString().slice(0, 10);
  const countKey = 'habit:count:' + todayKey;
  const lastTapKey = 'habit:lastTap';
  const goal = 8;

  let count = (await Loom.kv.get(countKey)) || 0;

  // Check if the widget button was tapped since last run
  const lastTap = await Loom.kv.get(lastTapKey);
  const lastRun = await Loom.kv.get('habit:lastRun');
  if (lastTap && (!lastRun || lastTap > lastRun)) {
    count = count + 1;
    await Loom.kv.set(countKey, count);
  }
  await Loom.kv.set('habit:lastRun', Date.now());

  // Calculate streak
  let streak = 0;
  for (let i = 0; i < 30; i++) {
    const d = new Date(Date.now() - i * 86400000).toISOString().slice(0, 10);
    const c = await Loom.kv.get('habit:count:' + d) || 0;
    if (c >= goal) streak++;
    else if (i > 0) break;
  }

  return { count, goal, streak, date: todayKey };
}, {
  name: 'Habits',
  description: 'Track daily habit completions.',
});
""",
        widgetTS: """
import { w } from '@loom/widget';

export const small = (ctx) => {
  const d = ctx.input || {};
  const count = d.count || 0;
  const goal = d.goal || 8;
  const pct = Math.min(count / goal, 1);
  return w.vstack([
    w.ring({ value: count, total: goal, label: String(count), caption: 'of ' + goal, color: 'accent' }),
    w.button({ label: '+ Log', kvKey: 'habit:lastTap', color: 'accent' }),
  ], { alignment: 'center' });
};

export const medium = (ctx) => {
  const d = ctx.input || {};
  const count = d.count || 0;
  const goal = d.goal || 8;
  return w.hstack([
    w.ring({ value: count, total: goal, label: String(count), caption: 'of ' + goal, color: 'accent' }),
    w.vstack([
      w.text('Today', { font: 'headline' }),
      w.text(count + ' / ' + goal + ' done', { font: 'subheadline', color: 'secondary' }),
      w.text(d.streak ? d.streak + ' day streak 🔥' : 'Start your streak!', { font: 'caption', color: 'secondary' }),
      w.spacer(),
      w.button({ label: '+ Log it', kvKey: 'habit:lastTap', color: 'accent' }),
    ], { alignment: 'leading' }),
  ]);
};

export const large = (ctx) => {
  const d = ctx.input || {};
  const count = d.count || 0;
  const goal = d.goal || 8;
  return w.vstack([
    w.text('Habits', { font: 'headline', color: 'secondary' }),
    w.spacer(),
    w.ring({ value: count, total: goal, label: String(count), caption: 'of ' + goal, color: 'accent' }),
    w.spacer(),
    w.progressBar({ value: count, total: goal, label: 'Progress', color: 'accent' }),
    w.spacer(),
    w.hstack([
      w.vstack([
        w.text(String(d.streak || 0), { font: 'title2' }),
        w.text('Day streak', { font: 'caption', color: 'secondary' }),
      ], { alignment: 'center' }),
      w.spacer(),
      w.button({ label: 'Log it', kvKey: 'habit:lastTap', color: 'accent' }),
    ]),
  ], { alignment: 'center' });
};
"""
    )

    // MARK: AI Quote (requires M4)

    static let aiQuote = ProjectTemplate(
        id: "aiQuote",
        displayName: "AI Quote",
        tagline: "Daily quote from on-device AI",
        icon: "quote.bubble.fill",
        requiresM4: false,
        defaultName: "AI Quote",
        mainTS: """
import { loom } from '@loom/core';

export default loom(async (ctx) => {
  const today = new Date().toISOString().slice(0, 10);
  const cacheKey = 'quote:' + today;

  // Re-use today's quote if already generated (delete this key in Database → KV to regenerate).
  const cached = await Loom.kv.get(cacheKey);
  if (cached) {
    console.log('Using cached quote for ' + today);
    return JSON.parse(cached);
  }

  console.log('Generating new quote via Loom.ai…');

  const prompt = [
    'Generate a short, original, inspiring quote about creativity, technology, or human potential.',
    'Reply with ONLY valid JSON in this format: {"quote":"...","author":"..."}',
    'The author should be a fictional name or just "Loom AI".',
  ].join(' ');

  const raw = await Loom.ai.complete({ prompt, maxTokens: 120, provider: 'auto' });
  console.log('AI response:', raw);

  let result;
  try {
    result = JSON.parse(raw.trim());
  } catch {
    result = { quote: raw.trim(), author: 'Loom AI' };
  }

  await Loom.kv.set(cacheKey, JSON.stringify(result));
  console.log('Quote cached for today.');
  return result;
}, {
  name: 'AI Quote',
  description: 'A fresh quote every day from on-device AI.',
  triggers: { schedule: '0 6 * * *' },
});
""",
        widgetTS: """
import { w } from '@loom/widget';

export const small = (ctx) => {
  const d = ctx.input || {};
  return w.vstack([
    w.icon('quote.opening', { size: 20, color: 'accent' }),
    w.spacer(),
    w.text(d.quote || 'Run to generate today\\'s quote.', { font: 'caption', lineLimit: 5 }),
  ], { alignment: 'leading' });
};

export const medium = (ctx) => {
  const d = ctx.input || {};
  return w.vstack([
    w.hstack([
      w.icon('quote.opening', { size: 18, color: 'accent' }),
      w.spacer(),
    ]),
    w.text(d.quote || 'Run to generate today\\'s quote.', { font: 'body', lineLimit: 4 }),
    w.spacer(),
    w.text('— ' + (d.author || 'Loom AI'), { font: 'caption', color: 'secondary' }),
  ], { alignment: 'leading' });
};

export const large = (ctx) => {
  const d = ctx.input || {};
  return w.vstack([
    w.spacer(),
    w.icon('quote.opening', { size: 32, color: 'accent' }),
    w.spacer(),
    w.text(d.quote || 'Run to generate today\\'s quote.', { font: 'title3', lineLimit: 6 }),
    w.spacer(),
    w.text('— ' + (d.author || 'Loom AI'), { font: 'subheadline', color: 'secondary' }),
    w.spacer(),
  ], { alignment: 'leading' });
};
"""
    )

    // MARK: Battery (requires M4)

    static let battery = ProjectTemplate(
        id: "battery",
        displayName: "Battery",
        tagline: "Battery level and charging status",
        icon: "battery.75percent",
        requiresM4: false,
        defaultName: "Battery",
        mainTS: """
import { loom } from '@loom/core';

export default loom(async (ctx) => {
  // Requires M4: Loom.device
  const level = await Loom.device.batteryLevel();         // 0.0 – 1.0
  const isCharging = await Loom.device.isCharging();
  const model = await Loom.device.model();
  const systemVersion = await Loom.device.systemVersion();

  const pct = Math.round(level * 100);
  let status, statusColor;
  if (isCharging)  { status = 'Charging'; statusColor = 'green'; }
  else if (pct > 50) { status = 'Good';   statusColor = 'green'; }
  else if (pct > 20) { status = 'OK';     statusColor = 'yellow'; }
  else               { status = 'Low';    statusColor = 'red'; }

  return { level, pct, isCharging, status, statusColor, model, systemVersion };
}, {
  name: 'Battery',
  description: 'Battery level and device info.',
});
""",
        widgetTS: """
import { w } from '@loom/widget';

export const small = (ctx) => {
  const d = ctx.input || {};
  const pct = d.pct || 0;
  const color = d.statusColor || 'secondary';
  return w.vstack([
    w.ring({ value: pct, total: 100, label: pct + '%', caption: d.status || '--', color: color }),
    d.isCharging ? w.icon('bolt.fill', { size: 14, color: 'green' }) : w.spacer(),
  ], { alignment: 'center' });
};

export const medium = (ctx) => {
  const d = ctx.input || {};
  const pct = d.pct || 0;
  const color = d.statusColor || 'secondary';
  return w.hstack([
    w.ring({ value: pct, total: 100, label: pct + '%', caption: d.status || '--', color: color }),
    w.vstack([
      w.text('Battery', { font: 'headline' }),
      w.text(d.status || '--', { font: 'subheadline', color: color }),
      w.spacer(),
      d.isCharging
        ? w.hstack([w.icon('bolt.fill', { size: 12, color: 'green' }), w.text(' Charging', { font: 'caption', color: 'green' })])
        : w.text(d.model || 'iPhone', { font: 'caption', color: 'secondary' }),
    ], { alignment: 'leading' }),
  ]);
};

export const large = (ctx) => {
  const d = ctx.input || {};
  const pct = d.pct || 0;
  const color = d.statusColor || 'secondary';
  return w.vstack([
    w.text('Battery', { font: 'headline', color: 'secondary' }),
    w.spacer(),
    w.ring({ value: pct, total: 100, label: pct + '%', caption: d.status || '--', color: color }),
    w.spacer(),
    w.divider(),
    w.hstack([
      w.icon(d.isCharging ? 'bolt.fill' : 'battery.75percent', { size: 14, color: color }),
      w.text(' ' + (d.isCharging ? 'Charging' : (d.model || 'iPhone')), { font: 'footnote', color: 'secondary' }),
      w.spacer(),
      w.text('iOS ' + (d.systemVersion || '--'), { font: 'footnote', color: 'tertiary' }),
    ]),
  ], { alignment: 'center' });
};
"""
    )
}
