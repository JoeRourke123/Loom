import { probeIf, INTERACTIVE } from './probe';

// speak makes noise, recognize needs the mic and a Done tap — both behind INTERACTIVE.
export async function speechSuite() {
  return [
    await probeIf(INTERACTIVE, 'speech.speak', 'speaks out loud', () =>
      Loom.speech.speak('Loom playground, speech check.')),

    await probeIf(INTERACTIVE, 'speech.recognize', 'needs the microphone', async () => {
      const heard = await Loom.speech.recognize();
      return heard === '' ? '"" — nothing transcribed' : heard;
    }),

    // Whether speak() actually waits for the utterance to finish, or resolves on dispatch.
    await probeIf(INTERACTIVE, 'speech.speak (resolves when finished?)', 'speaks out loud', async () => {
      const started = Date.now();
      await Loom.speech.speak('One two three four five six seven eight.');
      const ms = Date.now() - started;
      return ms > 1500 ? `${ms}ms — waited for the utterance` : `${ms}ms — returned early`;
    }),
  ];
}
