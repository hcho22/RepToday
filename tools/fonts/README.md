# Bundled fonts

The app's two typefaces live in `ios/RepToday/RepToday/Resources/Fonts/`, each beside its license:

- **Bricolage Grotesque** (`BricolageGrotesque-*.ttf`, license `BricolageGrotesque-OFL.txt`): headlines and every number.
- **Inter** (`Inter-*.ttf`, license `Inter-OFL.txt`): reading text.

Both are under the SIL Open Font License 1.1, which allows bundling them in a commercial app as long as the license travels with the fonts.
The files are registered through `UIAppFonts` in `ios/RepToday/RepToday/Info.plist` and read through `Theme.Typography`.

They are static instances cut from the official variable fonts in google/fonts, because `Font.custom(_:size:relativeTo:)` keeps Dynamic Type scaling but cannot set a variation axis, and Core Text does not pick an optical size for a custom font by itself.
`make-static-fonts.py` documents which instances exist and why, and regenerates them byte for byte from pinned source commits:

```bash
python3 -m pip install fonttools
python3 tools/fonts/make-static-fonts.py ios/RepToday/RepToday/Resources/Fonts
```
