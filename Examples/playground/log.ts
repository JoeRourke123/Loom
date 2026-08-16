import { probe } from './probe';

// Both logging surfaces. console.* aliases onto Loom.log.* (LoomBridge.wireConsole), so if one
// column of this table passes and the other doesn't, the aliasing is what broke.
export async function logSuite() {
  const at = new Date().toISOString();

  return [
    await probe('log.debug', () => Loom.log.debug('playground', { level: 'debug', at })),
    await probe('log.info', () => Loom.log.info('playground', { level: 'info', at })),
    await probe('log.warn', () => Loom.log.warn('playground', { level: 'warn', at })),
    // Expected in the console. A red line here is the probe working, not the API failing.
    await probe('log.error', () => Loom.log.error('playground', { level: 'error', at })),

    await probe('console.log', () => console.log('playground console.log')),
    await probe('console.info', () => console.info('playground console.info')),
    await probe('console.warn', () => console.warn('playground console.warn')),
    await probe('console.error', () => console.error('playground console.error')),

    // console.log stringifies through the same path as Loom.log — worth seeing what it does to a
    // non-string, because that's where the "[object Object]" surprises come from.
    await probe('console.log (object)', () => console.log({ nested: { a: 1 }, list: [1, 2, 3] })),
  ];
}
