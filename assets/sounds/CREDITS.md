# Sound effects — provenance and licensing

All six cues in this directory are **original, first-party assets**. No
third-party samples, loops, packs or recordings are included, and nothing is
fetched at runtime — the files are bundled with the app and played from local
`assets/`.

| File | Purpose | Length |
| --- | --- | --- |
| `ui_tap.wav` | Soft digital tick for button taps | 45 ms |
| `selection.wav` | Rounded confirmation tone for selection changes | 85 ms |
| `transaction_saved.wav` | Signature "cha-ching" after a transaction is persisted | 420 ms |
| `action_success.wav` | Two-note chime for a verified success | 360 ms |
| `action_failed.wav` | Quiet low tone for a reported failure | 340 ms |
| `milestone.wav` | Restrained three-note celebration for a verified milestone | 620 ms |

## How they were made

Each cue is synthesised procedurally by [`tool/generate_sounds.py`](../../tool/generate_sounds.py):
band-limited sine partials with exponential decays, a 2 ms anti-click fade on
both ends, and a conservative `-6 dBFS` peak. Only the Python standard library
is used, and the generator is fully deterministic, so re-running it reproduces
byte-identical output:

```bash
python tool/generate_sounds.py
```

Format: 16-bit mono PCM WAV, 44.1 kHz. Total bundled size is ~166 KB.

## Licence

To the extent that the generator and its output are copyrightable, they are
released by the SpendSense project under **CC0 1.0 Universal (public domain
dedication)** — https://creativecommons.org/publicdomain/zero/1.0/. They may be
used, modified and redistributed without attribution.

## Playback

Playback is handled by the `audioplayers` package (MIT), added in
`pubspec.yaml`. See `lib/services/sound_service.dart` for the player
implementation and `lib/providers/sound_provider.dart` for the user settings.
