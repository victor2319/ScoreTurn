# Shared C++ score-following engine: next milestone, NOT shipped in MVP-01

MVP-01 captures signed 16-bit PCM using `record` and implements a small
amplitude start gate in Dart. It does **not** claim that harmonic score following
from POC-24 has been ported to iOS/Android.

Suggested future FFI API:

```
autoscore_engine_create(sample_rate, hop_size)
autoscore_engine_load_score_landmarks(local_binary)
autoscore_engine_push_pcm(const int16_t* pcm, int frames)
autoscore_engine_get_position() // measure, beat, confidence
autoscore_engine_destroy()
```

FFT/Chroma/score matching should run off the audio callback thread. Mobile
microphone timing, interruptions and true page-turn accuracy remain to test.
