# Photo score following Implementation Plan

> Use superpowers:executing-plans for implementation.

**Goal:** Import photographs through OMR, review original-image overlays, follow
recognized notes offline and turn at the penultimate measure.
**Architecture:** Python Audiveris adapter returns normalized measures, note events,
source coordinates and MusicXML. Flutter stores a versioned document alongside
original photographs. A local chroma matcher drives a separate experimental reader.
**Tech Stack:** Flutter/Dart, Python standard library, Audiveris CLI.
**Spec:** ../specs/photo-following.md

## Global Constraints
- No network calls or reference recording prerequisite during performance.
- Preserve existing fixed BPM/manual reader and old catalog compatibility.
- No fabricated recognition or guessed image coordinates.
- No secret credentials in source or APK; no dependency upgrade unrelated to work.
- Penultimate measure is the default trigger; user corrections persist.

## Review Focus
- Repeats, endings, ties, multiple voices and silent measures.
- Photo orientation, resizing, invalid/missing measure bounds.
- Mic cancellation, lifecycle interruptions and stale callbacks.
- Incomplete recognition, HTTP failures and corrupt stored data.
- Repeated chords and noise must not cause a page jump.

## Task 1: Structure and import service
Files: server/recognize.py, server/test_recognize.py, lib/core/score_document.dart,
test/score_document_test.dart. Produce versioned JSON: pages, measures with bounds,
events with onset/duration/MIDI pitch, explicit performance order, warnings.
- [ ] Add fixtures for polyphonic MusicXML and Audiveris coordinates, invalid data.
- [ ] Run tests and observe failure; implement parser and validations; rerun green.
- [ ] Add bounded request handler and real Audiveris subprocess adapter.

## Task 2: Import review and persistence
Files: lib/core/recognition_client.dart, lib/ui/recognition_screen.dart,
lib/ui/annotated_page.dart, lib/ui/library_screen.dart.
- [ ] Test document bounds, triggers and edits, then implement local document store.
- [ ] Add HTTPS service upload, clear errors, page review and manual measure boxes.
- [ ] Add explicit library entry; no automatic upload without user action.

## Task 3: Offline follower and reader
Files: lib/core/score_follower.dart, lib/core/chroma.dart,
lib/ui/follow_screen.dart, test/score_follower_test.dart.
- [ ] Test variable tempo, silence/noise, adjacent repeated notes and manual seek.
- [ ] Implement streaming chroma and bounded score matching with confidence gate.
- [ ] Connect continuous mic, overlays, manual position correction and safe pause.
- [ ] Run Dart/Flutter tests, analyze and platform configuration tests.

## Task 4: Review and delivery
- [ ] Independent whole-change review, fix important findings with regression tests.
- [ ] Commit on feature branch, run Android/iOS CI, report exact verification and
      service setup requirements. Do not describe this as production-ready OMR.
