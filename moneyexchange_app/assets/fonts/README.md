# App font — TT Norms Pro

The app's typeface is **TT Norms Pro** (`AppTheme.fontFamily`). It is a **commercial,
licensed font**, so the actual font files are intentionally **not** committed to this
repo. Until they're added, the app renders in the platform default font (no crash).

## To activate TT Norms Pro

1. Obtain the licensed font files (from TypeType / your licence) and drop them here as:

   ```
   assets/fonts/TTNormsPro-Regular.otf
   assets/fonts/TTNormsPro-Medium.otf
   assets/fonts/TTNormsPro-Bold.otf
   ```

   (Weights can be `.otf` or `.ttf` — just match the filenames below.)

2. Uncomment the `fonts:` block at the bottom of `pubspec.yaml` (it's already written
   out, pointing at the filenames above).

3. `flutter pub get` and rebuild. `AppTheme.fontFamily` (`'TT Norms Pro'`) is already
   wired into the light and dark themes, so every screen picks it up automatically.
