# Asset attribution

Every third-party asset that ships inside the Rep Today binary must have a row here first.

The rule is deliberately hard: an asset with no recorded source and license is **not cleared for distribution**, so it stays out of the app target's bundle (`ios/RepToday/project.yml`, `Resources/`).
The exercise card degrades per movement on its own (a single pose, else the SF-Symbol glyph), so holding an asset back costs only that movement's art.

## Trainer pose art (US-TP01)

The male and female Trainer start and end poses shown on the exercise card and the rest overlay (ADR-0008).
They ship in `ios/RepToday/RepToday/Resources/Assets.xcassets/Trainer/`, one image set per exercise id, Trainer and pose, imported by `tools/import-trainer-art.py`.

| File | Embedded name | Source | License | Cleared to ship |
| --- | --- | --- | --- | --- |
| `Assets.xcassets/Trainer/male/*.imageset/*.png`, `Assets.xcassets/Trainer/female/*.imageset/*.png` (every Trainer image set) | `Trainer/<male\|female>/<exercise id>-<start\|end>` | Trainer characters and pose art generated with ChatGPT image generation (OpenAI) from text prompts for RepToday; no third-party artwork or real-person likeness used; OpenAI's terms for generated output apply; provenance retained in each art folder's generation log and manifest. | [OpenAI Terms of Use](https://openai.com/policies/terms-of-use/), "Content" - "Ownership of content": as between the user and OpenAI, the user owns the Output, and OpenAI assigns to the user its right, title and interest, if any, in the Output (terms effective January 1, 2026, re-read 2026-10-02). | Yes (2026-10-02) |

The generation logs, prompts, manifests and verification files stay with the art outside this repository; none is committed here.

## Typefaces (visual direction)

The two typefaces of the visual direction: Bricolage Grotesque for headlines and every number, Inter for reading text.
They ship as static cuts in `ios/RepToday/RepToday/Resources/Fonts/`, each family's license beside it, cut from the official variable fonts by `tools/fonts/make-static-fonts.py` (see `tools/fonts/README.md`).

| File | Embedded name | Source | License | Cleared to ship |
| --- | --- | --- | --- | --- |
| `Resources/Fonts/BricolageGrotesque-*.ttf` | `BricolageGrotesque-96ptExtraBold`, `-48ptExtraBold`, `-24ptExtraBold`, `-24ptBold` | Bricolage Grotesque by the Bricolage Grotesque Project Authors (https://github.com/ateliertriay/bricolage), from google/fonts `ofl/bricolagegrotesque` at commit `6ce172f74aa355ea43eb964fa4a91570a4d3064d`. | SIL Open Font License 1.1, `Resources/Fonts/BricolageGrotesque-OFL.txt` (bundled with the app). The cuts keep the original family name with an optical-size suffix, as the project's own static builds do; OFL allows modified versions under it and bundling in commercial software. | Yes (2026-11-14) |
| `Resources/Fonts/Inter-*.ttf` | `Inter-Regular`, `-Medium`, `-SemiBold`, `-Bold`, `-ExtraBold` | Inter by the Inter Project Authors (https://github.com/rsms/inter), from google/fonts `ofl/inter` at commit `0b58fb370093f9a9f4ff785d94405710b79de67c`. | SIL Open Font License 1.1, `Resources/Fonts/Inter-OFL.txt` (bundled with the app). | Yes (2026-11-14) |

## Icons and day marks (visual direction)

| File | Embedded name | Source | License | Cleared to ship |
| --- | --- | --- | --- | --- |
| `Assets.xcassets/Icons/*.imageset/*.svg`, `Assets.xcassets/Marks/*.imageset/*.svg` | `Icons/<name>`, `Marks/<mark>-<fill\|line>` | Drawn for Rep Today in the approved design handoff (the owner's own design work); converted to template vector images with their colors set to black so they tint. No third-party artwork. | Owned by the Rep Today project. | Yes (2026-11-14) |

## Removed assets

### `push_standard.json` (removed)

Added as the US-O01 validation fixture ("a single test `.json` dropped into `Resources`") to prove the Lottie seam and its fallback end to end, then **deleted from the repository**.

It was a third-party Lottie whose origin was never written down, so nobody could say what redistributing it would require.
Keeping it out of Copy Bundle Resources addressed the risk of shipping it inside the binary, but the file was still committed to a public repository - which is itself redistribution - so excluding it from the bundle was never enough.
Since its provenance could not be reconstructed, it was removed rather than kept as a repo-local fixture.

Nothing depended on it: no `Exercises.json` entry ever referenced it, and at the time the seam it validated was covered by `ExerciseDemoView`'s fallback path plus `ExerciseLibraryTests.testEveryAnimationNameResolvesToABundledFile`, which gated `animationName` against the bundle.
The whole animation seam has since been retired (US-TP12, ADR-0008): `Exercise.animationName`, the Lottie package and that test are gone, and the exercise card shows the static Trainer pose art above.
Any future asset still arrives with its source and license row **before** it is added to `Resources`.
