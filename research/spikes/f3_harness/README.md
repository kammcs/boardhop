# F3 harness

Pure-Dart round-trip of Azure DevOps HTML through the Delta-based editor converters (Quill, Fleather). Separate package so the app keeps none of these dependencies.

```
cd research/spikes/f3_harness
flutter test
```

Reads `../results/f3-samples.json` (gitignored; produced by `s13_html_samples.py`) when present and writes `../results/f3-roundtrip.md`.
