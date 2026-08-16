import { loom } from '@loom/core';
import { z } from 'zod';

// .md is one of the four editable extensions, so this file shows up in Loom's own editor
// alongside main.ts. Your notes are readable without leaving the app.
const NOTES = 'notes.md';

export default loom(async (ctx) => {
  // ctx.input is always an object — {} when there is no input — so this never throws.
  const spoken = String(ctx.input.text ?? '').trim();
  const text = spoken || await capture();

  if (!text) {
    Loom.log.warn('Nothing captured — note discarded.');
    return { saved: false };
  }

  const stamp = new Date().toISOString().slice(0, 16).replace('T', ' ');
  const existing = await readOrCreate();
  await Loom.files.write(NOTES, `${existing}- **${stamp}** ${text}\n`);

  const files = await Loom.files.list();
  Loom.log.info('Note saved', { file: NOTES, characters: text.length, filesInProject: files.length });

  return { saved: true, text, at: stamp };
}, {
  name: 'Quick Note',
  description: 'Appends a timestamped line to a notes file you can open in the Loom editor.',
  // Hands the result back to Shortcuts and to Siri, so "Quick Note buy milk" can be spoken back.
  returnsResult: true,
  intent: {
    inputs: z.object({
      // .describe() is what Siri matches natural language against. Without it, parameter inference
      // gets noticeably worse — the linter in the editor's Siri tab will tell you so.
      text: z.string().optional().describe('What to write down'),
    }),
  },
});

// Loom.files.read rejects when the file does not exist, so the first note has to create it.
async function readOrCreate(): Promise<string> {
  try {
    return await Loom.files.read(NOTES);
  } catch (error) {
    Loom.log.debug('No notes file yet — starting one.', { file: NOTES, reason: String(error) });
    return '# Notes\n\n';
  }
}

async function capture(): Promise<string> {
  const typed = await Loom.ui.input({ prompt: 'Quick note', placeholder: 'Type, or leave blank to dictate' });
  if (typed.trim()) return typed.trim();

  try {
    const heard = await Loom.speech.recognize();
    return heard.trim();
  } catch (error) {
    Loom.log.error('Dictation unavailable', { reason: String(error) });
    return '';
  }
}
