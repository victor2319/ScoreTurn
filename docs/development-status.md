# 0.3 development status — 2026-10-26

Implemented: original-photo measure overlays, versioned local music data, Audiveris
adapter, manual pitch/bounds/turn/order corrections, offline chroma follower,
confidence holds, manual position correction, early-turn tail display.

Regression evidence:
- Python: 8 parser/geometry/navigation tests pass.
- Standalone Dart: document, variable-tempo follower, repeat turn policy, real PCM
  framing/chroma, harmonic PCM -> follower integration, and canceled upload pass.
- CI run 40209691604: Flutter tests and analyze passed on Android/iOS; builds were
  in progress when this note was written. See Actions for final results.

The requested independent review did not finish because the review agent hit its
usage limit. It identified a photo-preload cancellation race, now fixed with a
failing-then-passing regression. Subsequent review was by the implementer.

Still unverified: real Audiveris recognition on the user's photos; complete OMR
adapter integration against an installed engine; real microphone accuracy on an
acoustic piano; tablet layout and lifecycle behavior on real devices. The engine
is not bundled and no HTTPS service has been deployed. Keep this as an experimental
development branch until these checks are complete.

Decisions: retain the old BPM reader; require review of recognition; hold rather
than guess on ambiguous audio; require manual order for unsupported navigation.
