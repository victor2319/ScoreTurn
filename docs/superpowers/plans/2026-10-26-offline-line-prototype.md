# Offline line-following prototype implementation plan

Goal: an installable offline prototype that follows original PDF/photos at system
(row) level and previews the next page on stable entry to the final system.
Approved scope: original score -> fast layout preparation -> microphone -> stable
last-line detection; no MusicXML or reference recording prerequisite. Preserve the
previous final row until the next page's first row is confirmed. Manual seek/pause
and no-backlog automatic turns are required. This is experimental, not validated
for stage performance.

Architecture: CYOLO MIT source and bundled weights, exported as fixed-shape ONNX
image predictor and audio-context model. Dart implements exact spectral features,
page raster preparation, system detection and conservative sequential state gate.
Native ONNX tasks run off the UI thread; queue overflow pauses listening rather
than processing stale audio. Each page and next-page candidate has separate state.
Only the first two pages are prepared before starting; remaining pages are prepared
one at a time on demand, with cached raster/layout. No scores or recordings are
bundled without authorization.

Task 1: export models, exact spectral/state parity test against original PyTorch;
include source commit, weight hash, license and deterministic export command.
Task 2: pure Dart layout and final-system state machine. Test wrong-order rows,
silence, stable final row, page handoff, manual seek and queue cancellation.
Task 3: Flutter page preparation/cache and ONNX inference, prototype reader,
manual controls, final-row strip, diagnostics, PDF/photo entry in library.
Task 4: CI unit tests/analyze, Android APK/iOS unsigned build. Report exact limits
and real-device follow-up without claiming measured phone accuracy.

Review focus: pause/lifecycle races, stale callbacks after page swap, repeated
page flips, poor row detection, altered image geometry, empty/rotated pages,
model failure and inability to keep up with real time. Self-check all before PR.
