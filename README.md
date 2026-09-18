

![FaceMac icon](Resources/Assets.xcassets/AppIcon.appiconset/icon_256x256.png)

# FaceMac

**Look at your Mac. It unlocks.**

Open-source face unlock for macOS — free, private, and it lives in your notch.
No subscription. No cloud. No account. Your face never leaves the machine.

**English** · [Русский](README.ru.md) · [中文](README.zh.md)

[![Download the latest release](https://img.shields.io/github/v/release/c1osed1/FaceMac?style=for-the-badge&label=Download&color=30D158&logo=apple&logoColor=white)](https://github.com/c1osed1/FaceMac/releases/latest)

![License: GPL v3](https://img.shields.io/badge/License-GPLv3-30D158.svg)
![Platform](https://img.shields.io/badge/macOS-14%2B-black.svg)
![Swift](https://img.shields.io/badge/Swift-6-orange.svg)
![Made on-device](https://img.shields.io/badge/on--device-100%25-30D158.svg)

## The pitch

You close the lid, you open it, the lock screen stares at you.

**FaceMac recognises you through the built-in camera and types your saved
password at your own lock screen.** The notch lights up, scans, draws a
checkmark, and you're in. About a second, all up, and the camera light goes off.

## Why people switch

- **Free, forever.** One binary, GPL-3.0, no trial, no licence key.
- **Private by construction.** Frames are never written to disk. Faceprints and
  your password never leave the machine.
- **The notch is the interface.** It grows out of the notch, pulses a green face
  glyph while it looks at you, then collapses into a tick.
- **Knows when it's not you.** A stranger gets rejected in ~0.4 s with a red shake.
- **The camera gets off.** 5 seconds without a match and it stops.
- **On-device ML.** SFace via CoreML, 128-d embeddings, calibrated per face.

## What it looks like

![FaceMac notch animation](docs/notch.gif)

![FaceMac settings](docs/settings.gif)

## Features


|                         |                                                                       |
| ----------------------- | --------------------------------------------------------------------- |
| Notch overlay           | Real `NSPanel` above everything, including the lock screen (SkyLight) |
| Face ID style animation | Green scan glyph → morph into a Lottie checkmark                      |
| Guided enrolment        | Five prompts — straight, left, right, tilt, tilt — with a live ring   |
| Rejection               | Confidently-not-you is caught instantly and shaken off in red         |
| Liveness                | Blink / micro-motion check rejects still photos, on-device            |
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
  → blink / micro-motion check                             (LivenessTracker)
  → type the Keychain password with CGEvent                (KeyboardInjector)
```

No frame is ever written to disk or sent anywhere.

## Install

### From a release (easiest)

Grab the [latest release](https://github.com/c1osed1/FaceMac/releases/latest),
drag **FaceMac** onto **Applications**, and on first launch right-click → **Open**
(builds aren't notarized yet).

### With Homebrew

Not in the official `homebrew/cask` tap yet (releases aren't notarized), so it
ships as its own tap:

```sh
brew tap c1osed1/facemac https://github.com/c1osed1/FaceMac.git
brew install --cask --no-quarantine c1osed1/facemac/facemac
```

The cask lives at [`Casks/facemac.rb`](Casks/facemac.rb).

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
- Built-in camera (Continuity Camera is not used)

Permissions are tied to a stable code signature, so a rebuild keeps the
Camera/Accessibility grants.

## Security, honestly

FaceMac is a **convenience**, not a security upgrade.

- An on-device liveness check (blink / natural micro-motion) rejects a still
photo, but it is not spoof-proof: a good video of you on a phone screen might
still get in. Turn it off or relax it in Settings → Recognition if it gets in
your way.
- It stores your macOS login password in the Keychain, because that's how it
types it for you. It never leaves the machine — but it *is* on the machine.
- It cannot lock you out: if it fails or you quit it, you log in exactly as before.
- Recognition never runs while the screen is unlocked; the camera is off unless
a scan is in progress.



## Build from source

```sh
swift build          # core library + CLI
swift test           # unit tests, incl. a CoreML vs ONNX parity test
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
  scripts/make-dmg.sh .build/ReleaseData/Build/Products/Release/FaceMac.app FaceMac-0.1.1.dmg
```

The CI build is ad-hoc signed, so macOS warns on first launch. Warning-free
builds need a paid Apple Developer account: sign with a **Developer ID
Application** certificate, notarize with `notarytool`, and staple the ticket.

## Roadmap

- [x] On-device SFace embeddings + per-face calibration
- [x] Notch overlay above the lock screen
- [x] Guided enrolment, instant rejection, lock-screen retry button
- [x] Liveness (blink / micro-motion)
- [x] Homebrew cask
- [ ] Multiple faces per Mac
- [ ] Pre-login (FileVault) support via a privileged helper



## Credits

- **SFace** — OpenCV Zoo, Apache-2.0. The recognition model.
- **Atoll** — GPL-3.0. The notch overlay approach.
- **SkyLightWindow** — MIT. Window above the lock screen.
- **Lottie** — Apache-2.0.

Not affiliated with Apple. "Face ID" is a trademark of Apple Inc.

## License

GPL-3.0 — see [LICENSE](LICENSE). Use it, fork it, ship it, just keep it open.