import { probe } from './probe';

// Synchronous, both of them. The write probe puts your original clipboard back, so running this
// suite doesn't cost you whatever you'd copied.
export async function clipboardSuite() {
  return [
    await probe('clipboard.read', () => {
      const text = Loom.clipboard.read();
      return text === '' ? '"" — empty pasteboard, or no text item on it' : text;
    }),

    await probe('clipboard.write', () => {
      const original = Loom.clipboard.read();
      Loom.clipboard.write('loom-playground');
      const back = Loom.clipboard.read();
      Loom.clipboard.write(original); // put it back
      return back === 'loom-playground'
        ? 'round-tripped, original restored'
        : `wrote 'loom-playground', read back '${back}'`;
    }),
  ];
}
