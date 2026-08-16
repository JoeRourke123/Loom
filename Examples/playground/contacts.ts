import { probe } from './probe';

// create → update → delete is a full round-trip that leaves your address book as it found it,
// which is why none of this needs the IRREVERSIBLE flag. If the suite fails partway through,
// look for "Loom Playground" in Contacts and delete it by hand.
export async function contactsSuite() {
  const results = [];
  let created: string | null = null;

  results.push(await probe('contacts.search', () => Loom.contacts.search('a')));

  results.push(await probe('contacts.create', async () => {
    const { id } = await Loom.contacts.create({
      givenName: 'Loom',
      familyName: 'Playground',
      emails: ['playground@example.com'],
      phones: ['+1 555 0100'],
    });
    created = id;
    return id;
  }));

  results.push(await probe('contacts.search (finds the new one)', async () => {
    const hits = await Loom.contacts.search('Loom Playground');
    // Only given/family name, emails, phones and id come back — nothing else is retrievable.
    return hits.length ? JSON.stringify(hits[0]) : 'NOT FOUND — create claimed success';
  }));

  results.push(await probe('contacts.update', () =>
    created
      ? Loom.contacts.update(created, { emails: ['updated@example.com'] })
      : Promise.reject(new Error('nothing was created to update'))));

  results.push(await probe('contacts.delete', () =>
    created
      ? Loom.contacts.delete(created)
      : Promise.reject(new Error('nothing was created to delete'))));

  results.push(await probe('contacts.search (gone again)', async () => {
    const hits = await Loom.contacts.search('Loom Playground');
    return hits.length === 0 ? 'cleaned up' : `LEAKED ${hits.length} contact(s) — delete by hand`;
  }));

  return results;
}
