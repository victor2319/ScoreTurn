# Photo score following (0.3 experimental)
Approved direction: display original photographs with measure overlays; retain a
separate parsed musical structure and image coordinate mapping. Import can use a
network OMR service. Performance must work fully offline. Reference recording is
optional, never a prerequisite. Multi-page boundaries determine the penultimate
measure turn trigger; allow manual correction. Hold on uncertain audio matches.

Implementation boundary: first provide a self-hosted Audiveris adapter (no assumed
paid account or hosted endpoint). Store recognition output locally and require a
review before following. Preserve original MusicXML alongside the normalized
structure. Unsupported navigation must be explicit, not silently flattened.
