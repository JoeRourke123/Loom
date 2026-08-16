import { probe, probeIf, IRREVERSIBLE } from './probe';

// Events round-trip (create → update → delete) and clean up after themselves.
// Reminders do NOT — there is no reminders.delete in the bridge, so that one is gated.
export async function calendarSuite() {
  const results = [];
  const start = new Date(Date.now() + 3600_000);
  const end = new Date(Date.now() + 5400_000);
  let created: string | null = null;

  results.push(await probe('calendar.events.list', () =>
    Loom.calendar.events.list({
      from: new Date().toISOString(),
      to: new Date(Date.now() + 7 * 86_400_000).toISOString(),
    })));

  results.push(await probe('calendar.events.create', async () => {
    const { id } = await Loom.calendar.events.create({
      title: 'Loom playground',
      start: start.toISOString(),
      end: end.toISOString(),
      notes: 'Created by the API playground. Deleted again a moment later.',
    });
    created = id;
    return id;
  }));

  results.push(await probe('calendar.events.update', () =>
    created
      ? Loom.calendar.events.update(created, { title: 'Loom playground (updated)' })
      : Promise.reject(new Error('nothing was created to update'))));

  // Deletes a single occurrence — worth remembering if you ever point this at a repeating event.
  results.push(await probe('calendar.events.delete', () =>
    created
      ? Loom.calendar.events.delete(created)
      : Promise.reject(new Error('nothing was created to delete'))));

  results.push(await probeIf(IRREVERSIBLE, 'calendar.reminders.create', 'no reminders.delete to undo it', () =>
    Loom.calendar.reminders.create({
      title: 'Loom playground — safe to delete',
      dueDate: start.toISOString(),
    })));

  return results;
}
