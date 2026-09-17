

![FaceMac icon](Resources/Assets.xcassets/AppIcon.appiconset/icon_256x256.png)

# FaceMac

**Look at your Mac. It unlocks.**

Open-source face unlock for macOS — free, private, and it lives in your notch.
No subscription. No cloud. No account. Your face never leaves the machine.

**English** · [Русский](README.ru.md) · [中文](README.zh.md)

![License: GPL v3](https://img.shields.io/badge/License-GPLv3-30D158.svg)
![Platform](https://img.shields.io/badge/macOS-14%2B-black.svg)
![Swift](https://img.shields.io/badge/Swift-6-orange.svg)
![Made on-device](https://img.shields.io/badge/on--device-100%25-30D158.svg)



---



## The pitch

You close the lid, you open it, the lock screen stares at you.
You type a password twenty times a day for no reason.

**FaceMac recognises you through the built-in camera and types your own saved
password at your own lock screen.** The notch lights up, scans, draws a
checkmark, and you're in — before you've finished sitting down. About a second,
all up, and the camera light goes off.

It's the thing MacGaze does, open-sourced, free, and hackable.

## Why people switch

- **Free, forever.** One binary, GPL-3.0, no trial, no licence key, no "family plan".
- **Private by construction.** A camera frame becomes measurements *on your Mac*.
Frames are never written to disk. Faceprints and your password never leave the machine.
- **The notch is the interface.** A real macOS notch overlay: it grows out of the
notch, pulses a green face glyph while it looks at you, then collapses into a tick.
- **Knows when it's not you.** A stranger gets rejected in ~0.4 s with a red shake,
not a 5-second wait.
- **The camera gets off.** 5 seconds without a match and it stops. The green light
is only on while it's actually looking.
- **Actually on-device ML.** SFace (Apache-2.0) via CoreML, 128-d embeddings,
calibrated per-face at enrolment.



## What it looks like

### The notch

![FaceMac notch animation](docs/notch.gif)

Scan → matched → rejected, all in the notch. No window, no dialog.

### Settings

![FaceMac settings](docs/settings.gif)

## Features


|                         |                                                                       |
| ----------------------- | --------------------------------------------------------------------- |
| Notch overlay           | Real `NSPanel` above everything, including the lock screen (SkyLight) |
| Face ID style animation | Green scan glyph → morph into a Lottie checkmark                      |
| Guided enrolment        | Five prompts — straight, left, right, tilt, tilt — with a live ring   |
| Rejection               | Confidently-not-you is caught instantly and shaken off in red         |
| Calibration             | The accept threshold is tuned to *your* face, camera and lighting     |
| Anti-drift              | Best-reference **and** centroid must agree, over N consecutive frames |
| Quality gates           | Tiny or heavily turned faces are ignored instead of guessed           |
| Retry button            | A glass button on the lock screen to try again                        |
| Bilingual+              | English, Русский, 中文 — system auto-detect or manual                   |
| Privacy                 | Everything local, camera stops when it's done                         |




## How it works

```
camera frame
  → Vision face detection + 5 landmarks
  → similarity alignment to the 112×112 ArcFace frame      (FaceAligner)
  → SFace CoreML embedding, 128-d, L2-normalised           (MLFaceEmbedder)
  → cosine similarity vs enrolment                         (FaceMatcher)
  → best + centroid + 3 consecutive frames must agree
  → type the Keychain password with CGEvent                (KeyboardInjector)
  → screenshot… no. Nothing is captured, ever.
```

No Python at runtime, no model server, no network call to recognise you.

## Install

### From a release (easiest)

1. Grab `FaceMac-x.y.z.dmg` from **Releases**.
2. Open it and drag **FaceMac** onto **Applications**.
3. First launch only: right-click the app → **Open**. Builds aren't notarized yet,
   so macOS asks once — after that it just works.

### From source

```sh
git clone https://github.com/<you>/FaceMac.git
cd FaceMac

scripts/fetch-model.sh   # builds the SFace CoreML model (once, needs Python 3.12+)
scripts/install.sh       # builds and installs to ~/Applications, then launches
```

### Then, from the menu bar icon

1. **Set Saved Password…** — your macOS login password, into the Keychain.
2. **Grant Accessibility…** — so it can type that password at the lock screen.
3. **Enroll Face…** — five quick head poses.
4. Keep **Enabled**, and lock your Mac (`⌃⌘Q`).

**Preview Notch Animation** shows you the whole thing without locking.

## Requirements

- Apple silicon Mac, macOS 14 or later
- Built-in camera (Continuity Camera is not used — your iPhone won't be there
when you're locked out)

Permissions are tied to a **stable code signature**. FaceMac signs with an
`Apple Development` identity so macOS keeps the Camera/Accessibility grants
across rebuilds; ad-hoc signing would make you re-approve every build.

## Security, honestly

FaceMac is a **convenience**, not a security upgrade.

- The built-in camera has no IR or depth sensor. A printed photo won't get in,
but a good video of you on a phone screen might. Apple's hardware solves this;
a webcam can't.
- It stores your macOS login password in the Keychain, because that's how it
types it for you. It never leaves the machine — but it *is* on the machine.
- It cannot lock you out: if it fails or you quit it, you log in exactly as before.
- Recognition never runs while the screen is unlocked; the camera is off unless
a scan is in progress.



## Build from source

```sh
swift build          # core library + CLI
swift test           # 22 unit tests, incl. a CoreML vs ONNX parity test
xcodegen generate    # produce FaceMac.xcodeproj
```

Layout:

```
Sources/
  FaceMacCore/     capture, Vision alignment, SFace embedder, matching,
                   Keychain, lock watcher, CGEvent input, coordinator
  FaceMacApp/      menu-bar app, notch overlay, settings window
  FaceMacDemo/     headless CLI (info / enroll / match)
Tools/Conversion/  SFace ONNX → CoreML conversion + golden-embedding generator
Tools/Icon/        app icon generator
scripts/           fetch-model.sh, install.sh
```



## Releasing

Releases are automated by GitHub Actions (`.github/workflows/ci.yml`):

- every push / PR builds the app and uploads a DMG artifact;
- a commit whose message contains `[RELEASE] 0.2.0`, or a manual run of the
  **Build** workflow, publishes a GitHub Release with that DMG attached;
- the version comes from `MARKETING_VERSION` in `project.yml` unless one is
  given explicitly.

Build it locally with:

```sh
xcodebuild -project FaceMac.xcodeproj -scheme FaceMac -configuration Release \
  -derivedDataPath .build/ReleaseData build
scripts/make-dmg.sh .build/ReleaseData/Build/Products/Release/FaceMac.app FaceMac-0.1.0.dmg
```

### Notarization

The CI build is ad-hoc signed, so macOS warns on first launch (right-click → Open).
To ship warning-free builds you need a paid Apple Developer account:
sign with a **Developer ID Application** certificate and notarize with
`notarytool`, then staple the ticket to the DMG. Wire the certificate and an
App Store Connect API key into repository secrets and add the signing steps to
the workflow — the DMG script already produces the artifact to notarize.

## Roadmap

- [x] On-device SFace embeddings + per-face calibration
- [x] Notch overlay above the lock screen, Face ID style animation
- [x] Guided enrolment, instant rejection, lock-screen retry button
- [ ] Liveness (blink / micro-motion)
- [ ] Multiple faces per Mac
- [ ] Pre-login (FileVault) support via a privileged helper
- [ ] Homebrew cask



## Credits

- **SFace** — OpenCV Zoo, Apache-2.0. The recognition model.
- **Atoll** — GPL-3.0. The notch overlay approach.
- **SkyLightWindow** — MIT. Window above the lock screen.
- **Lottie** — Apache-2.0.

Not affiliated with Apple. "Face ID" is a trademark of Apple Inc.

## License

GPL-3.0 — see [LICENSE](LICENSE). Use it, fork it, ship it, just keep it open.