import { probe, probeIf, INTERACTIVE } from './probe';

const SCRATCH = 'playground-scratch.txt';

export async function filesSuite() {
  return [
    await probe('files.write', () => Loom.files.write(SCRATCH, `written at ${new Date().toISOString()}`)),
    await probe('files.read', () => Loom.files.read(SCRATCH)),
    await probe('files.list', () => Loom.files.list()),
    await probeIf(INTERACTIVE, 'files.pick', 'opens the document picker', () => Loom.files.pick()),

    // Nested write — creates parent dirs, but note that the module resolver won't import from a
    // subfolder even though the filesystem happily has one.
    await probe('files.write (subfolder)', async () => {
      await Loom.files.write('playground-sub/nested.txt', 'nested');
      return await Loom.files.read('playground-sub/nested.txt');
    }),

    // The sandbox guard. A *pass* here means traversal was correctly refused; if this row goes
    // red, project scoping is broken and secrets.json is reachable from a script.
    await probe('files.read (../ must reject)', async () => {
      try {
        await Loom.files.read('../secrets.json');
      } catch (err) {
        return 'traversal rejected, as it should be';
      }
      throw new Error('../ ESCAPED THE PROJECT FOLDER — sandbox guard is gone');
    }),

    await probe('files.read (absolute must reject)', async () => {
      try {
        await Loom.files.read('/etc/passwd');
      } catch (err) {
        return 'absolute path rejected, as it should be';
      }
      throw new Error('an absolute path was READ — sandbox guard is gone');
    }),

    await probe('files.read (missing file)', async () => {
      try {
        await Loom.files.read('definitely-not-here.txt');
      } catch (err) {
        return `rejects with: ${(err as any)?.message ?? err}`;
      }
      throw new Error('reading a missing file resolved');
    }),
  ];
}
