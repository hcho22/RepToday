# Profile photo: validation

The user can take a photo with the camera or choose one from the library, crop it to a square, and see it on the Profile tab and the Account screen.
The photo is saved on the phone and copied to the account's Clerk profile image when signed in.
What was built is in `docs/implementation-log.md` ("Profile photo"); the unit coverage is the "Profile photo" row of `docs/test-coverage.md`.

- **Risk:** medium. It adds a camera permission and sends a personal image to the account provider (Clerk). The image goes only to the user's own account, removing the photo removes it there, and account deletion removes it before the account.
- **Impact:** the Profile tab and Account screen, a new app-private file store, the Clerk user profile (development and production instances), the camera usage string, the App Store privacy label.
- **Preserved:** with no photo set, Profile shows the same `sun` disc it always did (now with a camera badge) and Account shows its icon as before. Sign-in, sign-out and account deletion run as before; no permission prompt appears until the user chooses Take Photo.

## Environment

- Xcode 26.5 (17F42), a lane-owned iPhone 16 Simulator on iOS 26.5, erased before each walk.
- The Clerk development instance and Convex development deployment `courteous-dogfish-560`, through the Debug build's own configuration, signed in with Clerk test addresses (`+clerk_test`, code 424242).
- Observed 2026-11-16 on this branch.

## Scenarios

| Requirement | Expected | Observed | Result | Evidence |
| --- | --- | --- | --- | --- |
| Placeholder | No photo: the `sun` disc, a button VoiceOver reads "Profile photo, No photo" | As expected | Pass | `profile-placeholder.png`, `ProfilePhotoEvidenceTests` |
| Choices with no camera | Simulator: Choose from Library only, no Take Photo, no Remove Photo | As expected (an anchored popover on iOS 26) | Pass | `simulator/02-choices-no-photo.png` |
| Choose, crop, set | Library photo, adjusted with pinch and drag, becomes the round avatar | As expected | Pass | `simulator/04-crop.png`, `simulator/05-profile-photo-set.png`, `crop.png`, `profile-photo-set.png` |
| Saved on the phone | The photo survives a relaunch | As expected | Pass | Simulator walk (relaunch step), `FileProfilePhotoStoreTests` |
| Remove | Remove Photo appears once a photo is set; removing shows the placeholder | As expected | Pass | `simulator/08-choices-with-photo.png`, `simulator/09-removed.png` |
| Account screen | The photo beside the signed-in account | As expected | Pass | `account-photo.png` |
| Largest text size | The header stacks, nothing clipped | As expected | Pass | `profile-photo-set-ax5.png` |
| Upload, then a new phone | Signed in to Clerk dev: set a photo, sign out (erases the phone's copy), sign back in: the photo is adopted from the account | Adopted | Pass | `simulator/live-03-adopted-photo-1.png` |
| Replace | Replace with a different crop, same round trip: the replacement is adopted, not the first | The replacement, pixel for pixel in the header | Pass | `simulator/live-05-adopted-photo-2.png` |
| Remove from the account | Remove, same round trip: nothing adopted | Placeholder after 20 s | Pass | `simulator/live-06-after-remove-round-trip.png` |
| Account deletion | Deletion with a photo set runs and returns to onboarding; the account's image is removed before the account | Deletion completed in the walk; the image removal is proved by `ProfilePhotoTeardownTests` | Pass (removal unit-tested) | `ProfilePhotoTeardownTests` |
| Deletion that stops | A deletion refused before anything is deleted puts the image back | Owed again, restored by the next sync | Pass | `ProfilePhotoTeardownTests` |
| Offline and upload failure | The phone keeps its photo; the change stays owed and goes later | As expected | Pass (unit) | `ProfilePhotoSyncTests`, `ProfilePhotoModelTests` |
| Sign-out with a waiting photo | Upload first; one that cannot upload is an unsaved change | As expected | Pass (unit) | `ProfilePhotoTeardownTests` |
| Denied camera | Take Photo hidden; "Allow Camera in Settings" offered | Decision logic as expected | Pass (unit); untested on screen | `CameraAvailabilityTests` |
| Camera capture | Take Photo opens the front camera; the shot goes to the crop | Not run | Untested | The Simulator has no camera |
| Never to other services | No Coach, telemetry, Convex, proxy or Waitlist source names the photo | As expected; a planted reference fails the guard | Pass | `ProfilePhotoBoundaryGuardTests` |

Limitations:

- The account image was observed through the app (adopted after sign-in), not read from Clerk's Backend API, which needs the secret key; that the image is gone after deletion was not read from Clerk either.
- The walks used a Clerk test email account. Apple and Google sign-in were not walked; for a Google account Clerk copies the Google picture as the profile image, so a first sign-in shows it as the photo.
- The sample photos are the Simulator's own library and a macOS wallpaper; the hosted evidence uses a synthetic image.

## Device checks owed

1. Take Photo on an iPhone: the camera prompt appears only then, with the usage string; a photo taken goes through the crop and sets the avatar.
2. Refuse the camera, then reopen the choices: Take Photo is gone and "Allow Camera in Settings" opens Settings; allowing it there brings Take Photo back.
3. Airplane mode: set a photo, it shows at once; turn the connection back on and the account takes it (sign out and in to see it adopted).
4. Delete an account with a photo set, then confirm in the Clerk dashboard that the user and image are gone.

## Release

Code only; it rides the next TestFlight build. Nothing changes on the Convex deployments or in Clerk's configuration.

### App Store privacy label (needs the captain; not changed in App Store Connect)

Uploading the photo to the account adds one declaration, alongside the M3 ones in `artifacts/reports/accounts-m3/validation.md`:

| Category | Data type | Linked to the user | Tracking | Purpose |
| --- | --- | --- | --- | --- |
| User Content | Photos or Videos | Yes | No | App Functionality |

The camera itself is not a data type: a photo taken stays on the phone unless it becomes the profile photo.
The Privacy Policy (`gtm/03-site/privacy.html`) should also say that a profile photo the user sets is stored with their account by Clerk and deleted with the account; that text needs the same legal review as the rest of the policy before it is published.

## Recovery

- Containment: do not ship the build.
- A user removes the photo from the phone and the account with Remove Photo, or deletes the account.
- A later build that drops the feature leaves already uploaded account images in Clerk until each user removes them or deletes their account.
