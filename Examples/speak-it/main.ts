import { loom } from '@loom/core';

// Speech synthesis on a very long string ties up the run for a long time, and there is no way to
// stop it from the script side. Cap it.
const LIMIT = 4000;

export default loom(async (ctx) => {
  const text = await resolveText(ctx);

  if (!text.trim()) {
    await Loom.ui.alert({ title: 'Nothing to read', message: 'No text was shared, copied or typed.' });
    return { spoken: false };
  }

  const speech = text.length > LIMIT ? text.slice(0, LIMIT) + '…' : text;
  Loom.log.info('Speaking', { source: ctx.trigger, characters: speech.length, truncated: speech !== text });

  // Resolves when the last word finishes, not when playback starts.
  await Loom.speech.speak(speech);

  return { spoken: true, characters: speech.length };
}, {
  name: 'Speak It',
  description: 'Reads text aloud, taking it from the share sheet, the clipboard, or a prompt.',
});

// Three entry points, in order of how deliberate they are. ctx.trigger tells you which one you got:
// 'manual', 'shareSheet', 'urlScheme', 'shortcut', 'siri', 'backgroundRefresh', 'backgroundProcessing'.
async function resolveText(ctx): Promise<string> {
  if (ctx.trigger === 'shareSheet') {
    // Synchronous, and really just a re-read of ctx.input — it is not a separate channel.
    const shared = Loom.share.input();
    if (shared && shared.type !== 'image') {
      Loom.log.debug('Using shared item', { type: shared.type });
      return shared.value;
    }
    Loom.log.warn('Shared item was an image — nothing to read.');
  }

  const clipboard = Loom.clipboard.read();
  if (clipboard.trim()) {
    Loom.log.debug('Using the clipboard.');
    return clipboard;
  }

  // Cancelling resolves '' — indistinguishable from submitting an empty field, so treat both the
  // same way rather than trying to detect a cancel.
  return await Loom.ui.input({ prompt: 'Read aloud', placeholder: 'Type or paste something' });
}
