# Loom.speech

`Loom.speech` exposes two methods: text-to-speech playback and one-shot speech-to-text transcription. There is no voice selection, no streaming/partial-result callback into JS, and no cancel method for either operation.

## `Loom.speech.speak()`

Speaks text aloud using the device's text-to-speech engine.

```ts
await Loom.speech.speak("Starting recording now");
```

### Parameters

| Name | Type | Description |
|------|------|-------------|
| `text` | `string` | Text to speak. Coerced to a string (`toString()`); falls back to `""` if that fails. |

### Behavior

- Uses `AVSpeechSynthesizer` with a single `AVSpeechUtterance`.
- Voice is picked automatically from the device's current locale language code (`Locale.current.language.languageCode?.identifier`). It is **not selectable from JS**. If no voice is found for that language code, the utterance's voice ends up `nil` and the system falls back to its own default voice.
- The returned promise resolves once the utterance **finishes playing aloud** — this call waits for playback to complete, it is not fire-and-forget.

```ts
await Loom.speech.speak("This line blocks until it has been read out loud.");
Loom.log.info("done speaking");
```

### Return value

Returns `Promise<void>` — resolves with no value once playback finishes.

### Permission behavior

None. No permission prompt is requested for text-to-speech output.

### Throws / rejects

Never rejects. There is no error path wired up for `speak()` — whatever text you pass, the promise always resolves once (or if) playback finishes.

## `Loom.speech.recognize()`

Records from the microphone and transcribes speech to text using on-device speech recognition. Recording is manually stopped by the user via a system alert.

```ts
try {
  const transcript = await Loom.speech.recognize(); // user taps "Done" to stop
  Loom.log.info(transcript);
} catch (e) {
  // e.g. "Microphone permission denied", "Speech recognizer not available"
}
```

### Parameters

None.

### Behavior

1. Requests **Speech Recognition** permission (`SFSpeechRecognizer.requestAuthorization`).
2. Requests **Microphone** permission (`AVAudioApplication.requestRecordPermission`).
3. Checks that a speech recognizer is available for the current locale, before any audio session work.
4. Starts recording: taps the audio input (buffer size 1024) and streams it into a speech recognition request with partial results enabled, continuously updating an internal transcript as speech is recognized.
5. Presents a `"Listening…"` system alert with a single **Done** button.
6. When the user taps **Done**, recording stops and the promise resolves with the transcript accumulated up to that point.

There is **no timeout and no silence-detection auto-stop** — recording continues indefinitely until the user taps Done. The returned promise stays pending the whole time.

If no view is available to present the "Listening…" alert, recognition finishes immediately, typically producing an empty or near-empty transcript rather than an error.

### Return value

Returns `Promise<string>` — the transcript accumulated up to the point the user tapped Done. May be `""` if nothing was captured (e.g. the alert couldn't be presented, or Done was tapped before any speech was recognized).

```ts
const transcript: string = await Loom.speech.recognize();
```

### Permission behavior

Two sequential system prompts are required, in this order:

| Step | Prompt | On denial |
|------|--------|-----------|
| 1 | Speech Recognition authorization | Rejects with `"Speech recognition permission denied"` |
| 2 | Microphone permission | Rejects with `"Microphone permission denied"` |

Both prompts fire (in order) every time authorization has not already been granted — subsequent calls after the user has answered are a no-op check, not a repeated prompt.

### Throws / rejects

| Condition | Rejection value |
|-----------|------------------|
| Speech Recognition permission not granted | `"Speech recognition permission denied"` |
| Microphone permission not granted | `"Microphone permission denied"` |
| No speech recognizer available for the current locale, or recognizer unavailable | `"Speech recognizer not available"` |
| Audio session setup or `engine.start()` throws | The underlying error's localized description |

Once recording has actually started successfully, there is **no explicit reject path** — the promise only resolves, via the Done button (or the no-top-view fallback), always with a string (possibly empty).

## Limitations

- No voice selection for `speak()` — voice is derived from the device locale, not choosable from JS.
- `speak()` never rejects, even on synthesis failure.
- `recognize()` has no timeout or silence detection — a script cannot bound how long it waits for the user to finish speaking and tap Done.
- No partial-result callback — a script only receives the final transcript when `recognize()` resolves, not incremental updates while the user is speaking.
- No cancel method for either `speak()` or `recognize()` once started.

## See Also

- [Overview](loom-doc://api-reference/overview.md)
- [Loom.device](loom-doc://api-reference/device.md)
- [Permissions & Privacy](loom-doc://guides/permissions-privacy.md)
- [Troubleshooting](loom-doc://troubleshooting/troubleshooting.md)
