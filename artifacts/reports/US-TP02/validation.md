# US-TP02 validation - bundled Trainer art and app size

Date: 2026-10-02.
Branch: `fm/reptoday-trainer-images`.

## Import

`python3 tools/import-trainer-art.py <copy of the art root>`, run against a copy of the captain's art folders after re-checking them (the back folder still holds 11 PNGs per Trainer, unchanged from the PRD's inventory).

- Imported 284 image sets (142 per Trainer), 16,738,228 bytes of PNG, each copied byte-for-byte at its untrimmed 600x600 canvas into `Resources/Assets.xcassets/Trainer/<male|female>/<exercise id>-<start|end>.imageset` (single scale, universal, render as original).
- Skipped and named by the script: the six Prone Y/T/W variant files (no catalog movement) and the twelve Gorilla Walk, Lizard Crawl and Underswitch files (`version2`, decision 16).
- No PNG carries text metadata (only `IHDR`, `iCCP`, `pHYs`, `IDAT`, `IEND` chunks), so no local path or personal data ships inside the art.
- No image set is tagged for On-Demand Resources; nothing is downloaded at runtime.

## App size

Release build for a generic iOS device (`-configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`), `main` at `ab04d6a` against this branch.

| Measure | Before (`main`) | After (branch) | Delta |
| --- | --- | --- | --- |
| `RepToday.app` (sum of file bytes) | 12,090,245 | 19,354,559 | +7,264,314 |
| `RepToday.app` (`du -sk`) | 11,836 KB | 18,920 KB | +7,084 KB |
| `Assets.car` | 49,288 | 11,399,160 | +11,349,872 |
| `RepToday` executable | 11,971,136 | 7,886,848 | -4,084,288 |
| `Lottie_Lottie.bundle` | 8 KB | gone | |

The art adds 11.35 MB to the compiled catalog: `actool` stores it losslessly in less than the 16.7 MB of raw PNG (`TrainerTests.testTheTwoCossackSquatsResolveToTheirOwnUntrimmedArt` proves the decoded pixels equal the committed PNGs).
Removing the statically linked Lottie package (US-TP12) takes 4.08 MB out of the executable, so the app grows by about 7.3 MB net, inside the 15-20 MB the captain was told.
App Store thinning and encryption change the download size; this is the unsigned build-product size.

## Offline

All art is in the binary's asset catalog and resolved with `UIImage(named:in:with:)`; there is no network path for it.
The Airplane-Mode step on a device is part of the captain's manual QA in `artifacts/reports/US-TP13/validation.md`.
