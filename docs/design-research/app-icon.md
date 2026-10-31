# SpendSense app icon

The launcher icon is a **luminous cycle ring with an ascending line** on a deep
Premium Blue field — the same visual language as the Home hero and launch
screen. The ring reads as a budget cycle; the line and lit endpoint read as
progress. No lettering, no skeuomorphic card, no AI-gradient blob.

## Artwork

| Asset | Use |
|---|---|
| `assets/icons/app_icon.png` | Legacy Android mipmaps and the full iOS set. Opaque 1024². |
| `assets/icons/app_icon_foreground.png` | Adaptive-icon foreground (transparent, content inside the 66% safe zone). |
| `android/.../drawable/ic_launcher_background.xml` | Adaptive background gradient `#021024 → #052659 → #0A3468`. |

Palette-derived construction:

- deep-navy diagonal field (`#021024 → #052659 → #0A3468`);
- brand/ice ring (`#5483B3 → #C1E8FF`) with a light-glow pass;
- frosted centre disc;
- white ascending line with an ice-blue endpoint.

## Regenerating

```bash
python tool/generate_app_icon.py
dart run flutter_launcher_icons
```

The generator is deterministic (Pillow, 2048² supersampled to 1024²).

After `flutter_launcher_icons`, keep the adaptive XML pointing at the gradient
drawable rather than a colour resource:

```xml
<background android:drawable="@drawable/ic_launcher_background"/>
<foreground android:drawable="@drawable/ic_launcher_foreground"/>
```

Flutter's generator may rewrite that block when the background is configured as
a drawable; this manual two-line fix is part of the regeneration step.

The launch screen's `AppLogo` uses the same `app_icon.png`, so the launcher,
native splash and Flutter launch moment all show the same mark.
