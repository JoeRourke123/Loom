# Loom.contacts

`Loom.contacts` searches, creates, updates, and deletes entries in the device's Contacts (Address Book) store. It is backed by `CNContactStore` — one store instance per bridge instance.

## Permissions

Every method — `search`, `create`, `update`, `delete` — independently requests Contacts access before it runs. There is no shared or cached permission check inside Loom: each call is a self-contained permission-plus-action unit.

- The first call in the app's lifetime shows the system permission prompt. iOS itself remembers the user's grant/deny decision after that — Loom does not cache it, but the OS does, so later calls don't show a second prompt.
- If access is denied or not granted, the call rejects with the literal string:

```
Contacts permission denied
```

- If `CNContactStore` itself returns an error (for reasons other than permission), the call rejects with that error's `localizedDescription`.

## `Loom.contacts.search()`

Searches contacts by name.

```ts
const results = await Loom.contacts.search("Jane");
for (const c of results) {
  Loom.log.info(`${c.firstName} ${c.lastName}`, { emails: c.emails });
}
```

| Name | Type | Description |
|------|------|-------------|
| `query` | `string` (optional) | Name to match against contacts. Omit it (or pass `''`) to enumerate **every** contact. |

`query` is matched with `CNContact.predicateForContacts(matchingName:)` — a substring/name match, not a raw predicate or query language. With no query the predicate is dropped entirely and the whole address book is enumerated, which is how you ask a question like "everyone with a birthday this month".

Returns `Promise<ContactRecord[]>`.

**`ContactRecord` shape:**

| Name | Type | Description |
|------|------|-------------|
| `id` | `string` | The contact's identifier. |
| `firstName` | `string` | Given name. |
| `lastName` | `string` | Family name. |
| `emails` | `string[]` | Email addresses. |
| `phones` | `string[]` | Phone numbers. |
| `birthday` | `PartialDate` (optional) | **Absent entirely** when the contact has no birthday set — test with `if (c.birthday)`. |
| `dates` | `PartialDate[]` | Other labelled dates (anniversaries and so on). Always an array; empty when there are none. |

**`PartialDate` shape:**

| Name | Type | Description |
|------|------|-------------|
| `month` | `number` | 1–12. Always present. |
| `day` | `number` | 1–31. Always present. |
| `year` | `number` (optional) | **Frequently absent** — a birthday with no year is normal, not an error. |
| `label` | `string` | On `dates` entries only, localized (`"Anniversary"`). `''` when unlabelled. |

Contacts store these as date *components*, not timestamps, which is why they aren't ISO strings: a year-less birthday has no point on the calendar to serialize. Guard on `year` before computing an age.

```ts
const all = await Loom.contacts.search();
const withBirthdays = all.filter((c) => c.birthday);
for (const c of withBirthdays) {
  const age = c.birthday.year ? new Date().getFullYear() - c.birthday.year : null;
  Loom.log.info(`${c.firstName} — ${c.birthday.day}/${c.birthday.month}`, { age });
}
```

**Limitations:** the fetched fields are fixed to given name, family name, emails, phones, identifier, birthday, and dates. Nothing else is retrievable through Loom — no postal addresses, organization, or contact image. Enumerating every contact is a full address-book walk on the script thread; on a large address book that is not instant.

`birthday` and `dates` are **read-only**. `create()` and `update()` ignore them — passing a record straight back to `update()` silently drops both fields rather than erroring.

## `Loom.contacts.create()`

Creates a new contact.

```ts
const { id } = await Loom.contacts.create({
  firstName: "Jane",
  lastName: "Doe",
  emails: ["jane@example.com"],
  phones: ["+1 555 0100"],
});
```

| Name | Type | Description |
|------|------|-------------|
| `givenName` or `firstName` | `string` (optional) | Given name. If both are supplied, `givenName` takes priority. |
| `familyName` or `lastName` | `string` (optional) | Family name. If both are supplied, `familyName` takes priority. |
| `emails` | `string[]` (optional) | Email addresses to add. |
| `phones` | `string[]` (optional) | Phone numbers to add. |

All fields are optional. Returns `Promise<{ id: string }>`, where `id` is the new contact's identifier.

**Limitations:** every email is saved under the `CNLabelWork` label and every phone number under `CNLabelPhoneNumberMain`. There is no way to set a per-entry label (e.g. "home", "mobile") from JS.

Same permission-request and rejection behavior as `search()`.

## `Loom.contacts.update()`

Updates an existing contact.

```ts
await Loom.contacts.update(id, { emails: ["jane.doe@example.com"] });
```

| Name | Type | Description |
|------|------|-------------|
| `id` | `string` | Identifier of the contact to update. |
| `fields` | `object` | Same shape as `create()`'s `fields` — `givenName`/`firstName`, `familyName`/`lastName`, `emails`, `phones`, all optional. |

Loom fetches the existing contact by `id`, applies the given fields on top of the current values, and saves the change.

Returns `Promise<void>` — resolves with `undefined` on success.

**Throws / rejects** with the underlying error's `localizedDescription`, including cases where the contact isn't found. There is no bespoke "not found" message here.

## `Loom.contacts.delete()`

Deletes a contact.

```ts
await Loom.contacts.delete(id);
```

| Name | Type | Description |
|------|------|-------------|
| `id` | `string` | Identifier of the contact to delete. |

Returns `Promise<void>` — resolves with `undefined` on success.

## See Also

- [Overview](loom-doc://api-reference/overview.md)
- [Loom.calendar](loom-doc://api-reference/calendar.md)
- [Permissions & Privacy](loom-doc://guides/permissions-privacy.md)
- [loom() Config](loom-doc://api-reference/loom-config.md)
