// Shared harness for the API playground. Nothing here is clever — it calls a thing, catches
// whatever comes back, and times it.
//
// Every probe is labelled with its LoomAPICatalog path ('db.table.insert', not 'insert a row').
// That label is exactly what ExampleCatalog.runPlaygroundCoverageCheck() greps for, so renaming
// one to something friendlier fails the DEBUG launch check. Keep them verbatim.

/** ui.*, files.pick, photos.pick, camera.capture, speech.* — anything needing a tap or the mic. */
export const INTERACTIVE = false;

/** The three calls that leave something behind Loom has no API to remove again. */
export const IRREVERSIBLE = false;

export type Result = {
  api: string;
  /** true passed, false threw, null skipped. */
  ok: boolean | null;
  ms: number;
  note: string;
};

export async function probe(api: string, fn: () => any): Promise<Result> {
  const started = Date.now();
  try {
    const value = await fn();
    return { api, ok: true, ms: Date.now() - started, note: preview(value) };
  } catch (err) {
    // Bridge rejections arrive as Error, but a rejected string is possible too (notify does it).
    return { api, ok: false, ms: Date.now() - started, note: String((err as any)?.message ?? err) };
  }
}

export function skip(api: string, why: string): Result {
  return { api, ok: null, ms: 0, note: `skipped — ${why}` };
}

export function probeIf(enabled: boolean, api: string, why: string, fn: () => any): Promise<Result> {
  return enabled ? probe(api, fn) : Promise.resolve(skip(api, why));
}

/** JSON.stringify that never throws and never floods the console. */
export function preview(value: any): string {
  if (value === undefined) return 'undefined';
  if (value === null) return 'null';
  if (typeof value === 'string') return clip(value);
  try {
    return clip(JSON.stringify(value));
  } catch (err) {
    return clip(String(value)); // circular, or a host object JSON can't walk
  }
}

/** First image already sitting in the project folder — camera.ocr and photos.save both need one. */
export async function findImage(): Promise<string | null> {
  const files = await Loom.files.list();
  return files.find((f: string) => /\.(jpe?g|png|heic)$/i.test(f)) ?? null;
}

function clip(text: string): string {
  return text.length > 140 ? text.slice(0, 140) + '…' : text;
}
