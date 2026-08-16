import { probe } from './probe';

// Synchronous, and only meaningful when ctx.trigger === 'shareSheet'. On a manual run it returns
// undefined — that's a pass, not a failure.
//
// To exercise it properly: share a link or an image into Loom from another app and pick this
// project. An image arrives as a project-relative filename, already copied into the folder.
export async function shareSuite(trigger: string) {
  return [
    await probe('share.input', () => {
      const shared = Loom.share.input();
      if (!shared) {
        return trigger === 'shareSheet'
          ? 'undefined on a shareSheet run — that IS a bug'
          : `undefined — expected, this run was triggered by '${trigger}'`;
      }
      return `${shared.type}: ${shared.value}`;
    }),

    // It's documented as a plain re-read of ctx.input, so the two must agree.
    await probe('share.input (matches ctx.input)', () => {
      const shared = Loom.share.input();
      return shared ? JSON.stringify(shared) : 'nothing shared into this run';
    }),
  ];
}
