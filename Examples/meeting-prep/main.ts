import { loom } from '@loom/core';
import { w } from '@loom/widget';

const BRIEFED = 'briefed';

export default loom(async (ctx) => {
  const now = new Date();
  const endOfDay = new Date(now);
  endOfDay.setHours(23, 59, 59, 0);

  const events = (await Loom.calendar.events.list({
    from: now.toISOString(),
    to: endOfDay.toISOString(),
  })).filter((event) => !event.allDay);

  if (!events.length) {
    Loom.log.info('Nothing left today.');
    return { events: [], next: null };
  }

  const next = events[0];
  const people = await findPeople(next);

  // Only brief each meeting once, however often this runs.
  const alreadyBriefed = Loom.kv.get(BRIEFED) === next.id;
  const brief = alreadyBriefed ? Loom.kv.get('lastBrief') : await writeBrief(next, people, ctx);

  if (!alreadyBriefed) {
    Loom.kv.set(BRIEFED, next.id);
    Loom.kv.set('lastBrief', brief);
    await scheduleReminders(next, brief);
  }

  Loom.log.info('Prepared', { meeting: next.title, attendees: people.length, reused: alreadyBriefed });

  return {
    next: {
      id: next.id,
      title: next.title,
      start: next.start,
      startsIn: minutesUntil(next.start),
      calendar: next.calendar,
      people: people.map((p) => `${p.firstName} ${p.lastName}`.trim()),
    },
    brief,
    later: events.slice(1, 5).map((e) => ({ title: e.title, start: e.start })),
  };
}, {
  name: 'Meeting Prep',
  description: 'Reads what is left of your day, looks up who you are meeting, and briefs you before it starts.',
  permissions: ['calendar', 'contacts', 'reminders'],
  triggers: { backgroundRefresh: true },
  widget: { refreshAfter: 900 },
});

// Calendar events do not expose structured attendees here, so names come from the notes and title.
// Capitalised word pairs are a crude but effective heuristic — and every hit is verified against
// the real address book before it is used.
async function findPeople(event) {
  const text = `${event.title} ${event.notes ?? ''}`;
  const candidates = [...new Set((text.match(/\b[A-Z][a-z]{2,}\s+[A-Z][a-z]{2,}\b/g) ?? []))].slice(0, 4);

  const found = [];
  for (const name of candidates) {
    try {
      const matches = await Loom.contacts.search(name);
      if (matches.length) found.push(matches[0]);
    } catch (error) {
      Loom.log.warn('Contacts unavailable', { reason: String(error) });
      break;
    }
  }
  return found;
}

// chat() rather than complete() — a short exchange steers the model's register better than one
// long prompt. On the on-device provider the turns are concatenated into a single request.
async function writeBrief(event, people, ctx) {
  const roster = people.length
    ? people.map((p) => `${p.firstName} ${p.lastName} (${p.emails[0] ?? 'no email'})`).join(', ')
    : 'no attendees identified';

  try {
    return await Loom.ai.chat([
      { role: 'user', content: 'You help me walk into meetings prepared. Be blunt and specific.' },
      { role: 'assistant', content: 'Understood. Give me the meeting and I will give you three bullets and one question worth asking.' },
      {
        role: 'user',
        content: [
          `Meeting: ${event.title}`,
          `Starts: ${event.start}`,
          `Calendar: ${event.calendar}`,
          `Attendees: ${roster}`,
          `Notes: ${(event.notes ?? '').slice(0, 600) || 'none'}`,
          `Triggered by: ${ctx.trigger}`,
        ].join('\n'),
      },
    ], { instructions: 'Three short bullets, then one question. Under 80 words total. No preamble.' });
  } catch (error) {
    Loom.log.warn('AI unavailable, falling back to the raw notes.', { reason: String(error) });
    return (event.notes ?? '').slice(0, 300) || 'No notes on this meeting.';
  }
}

async function scheduleReminders(event, brief: string) {
  const start = new Date(event.start);
  const alert = new Date(start.getTime() - 15 * 60_000);

  if (alert > new Date()) {
    await Loom.notify.schedule({
      title: `${event.title} in 15 minutes`,
      body: brief.slice(0, 160),
      // ISO 8601 with fractional seconds. An unparseable date silently becomes "in five seconds"
      // rather than throwing, so getting this format right matters.
      trigger: { date: alert.toISOString() },
    });
  }

  await Loom.calendar.reminders.create({
    title: `Prep: ${event.title}`,
    dueDate: alert.toISOString(),
  });
}

const minutesUntil = (iso: string) => Math.round((new Date(iso).getTime() - Date.now()) / 60_000);

export const widget = (ctx) => {
  const d = ctx.data;
  if (!d?.next) {
    return w.vstack([
      w.icon('checkmark.circle.fill', { size: 22, color: 'green' }),
      w.text('Nothing left today.', { font: 'caption', color: 'secondary' }),
    ], { spacing: 6, padding: 14 });
  }

  const soon = d.next.startsIn <= 15;
  const countdown = d.next.startsIn < 0
    ? 'now'
    : d.next.startsIn < 60
      ? `${d.next.startsIn} min`
      : `${Math.round(d.next.startsIn / 60)} hr`;

  return {
    small: w.vstack([
      w.capsule([w.text(countdown, { font: 'caption2', bold: true, color: 'white' })], {
        color: soon ? 'red' : 'blue',
        padding: 6,
      }),
      w.text(d.next.title, { font: 'callout', bold: true, lineLimit: 3 }),
      w.spacer(),
      w.text(d.next.people.join(', ') || d.next.calendar, { font: 'caption2', color: 'secondary', lineLimit: 1 }),
    ], { spacing: 5, padding: 12, alignment: 'leading' }),

    medium: w.vstack([
      w.label({
        icon: soon ? 'exclamationmark.circle.fill' : 'calendar',
        title: d.next.title,
        subtitle: `${countdown} · ${d.next.people.join(', ') || d.next.calendar}`,
        color: soon ? 'red' : 'accent',
      }),
      w.divider(),
      w.text(d.brief, { font: 'caption', lineLimit: 4 }),
    ], { spacing: 8, padding: 12, alignment: 'leading' }),

    large: w.vstack([
      w.label({
        icon: soon ? 'exclamationmark.circle.fill' : 'calendar',
        title: d.next.title,
        subtitle: `${countdown} · ${d.next.calendar}`,
        color: soon ? 'red' : 'accent',
      }),
      w.divider(),
      w.text(d.brief, { font: 'caption', lineLimit: 8 }),
      w.spacer(),
      ...d.later.map((event) => w.hstack([
        w.text(String(event.start).slice(11, 16), { font: 'caption2', color: 'secondary' }),
        w.text(event.title, { font: 'caption2', lineLimit: 1 }),
      ], { spacing: 8 })),
    ], { spacing: 8, padding: 14, alignment: 'leading' }),
  };
};
