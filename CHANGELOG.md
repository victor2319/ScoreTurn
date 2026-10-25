## 0.3.0+3 — experimental photo following

- Add Audiveris import adapter, local music structure and original-image measure overlays.
- Add manual bounds, note-pitch, performance-order and turn-point correction.
- Add continuous offline chroma following with confidence hold and manual repositioning.
- Keep previous-page tail visible during early page turn; preserve the old BPM reader.
- Add explicit import-only network permission; no network calls in performance path.
- Requires self-hosted OMR or locally generated recognition JSON; not a hosted turnkey service.

# AutoScore changes

## MVP-02 (0.2.0+2)

- Correct unsupported `file_picker` v13 `allowMultiple` argument.
- Add pure-Dart `TurnPolicy` with crossing-only turns and manual repositioning safeguards.
- Add associated Flutter unit tests for page transitions, time jumps and resume.
- Add photo preview of upcoming page, keeping active page visible.
- Add BPM +/- 5 live manual adjustment without losing musical beat position.
- Add local JSONL event-only session diagnostics with clipboard export (no PCM saved).
- Guard cancellation while requesting microphone permission or opening native PCM stream.
- Add iOS 14 deployment configuration (required by file_picker v13) and Android/iOS CI build recipe.
- Reduce paused UI redraws, wrap narrow-screen page controls.
- Maintain offline runtime; harmonic score confirmation remains unimplemented.

## MVP-01 (0.1.0+1)

- Flutter reader and local score import.
- PCM amplitude onset detector and beat timer based automatic page turning.
- Manual reader controls and basic platform permission scripts.
