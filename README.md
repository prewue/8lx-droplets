<div align="center">

# 8lx droplets

**Extensions for [Droppy](https://getdroppy.app), the Dynamic Island and shelf for Mac.**

Crafted by [8lx](https://8lx.vision)

[![Release](https://img.shields.io/github/v/release/prewue/8lx-droplets?label=release&color=5E5CE6)](https://github.com/prewue/8lx-droplets/releases/latest)
![Droppy](https://img.shields.io/badge/Droppy-15.3%2B-111111)
![macOS](https://img.shields.io/badge/macOS-14%2B-111111?logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)
[![License](https://img.shields.io/badge/license-MIT-2EA043)](LICENSE)

</div>

---

Droplets are small apps that live inside Droppy: on the notch, on the shelf under it and in Droppy's Settings. Each one here is its own [DroppyKit](https://gitlab.com/droppyformac1/droppykit) package in its own folder.

| Droplet | What it does | Version |
| :-- | :-- | :-: |
| [**Brightnesss**](brightnesss) | XDR past 100% and dimming below zero, from the notch | 1.0.0 |
| [**Freelancy**](freelancy) | Bill by the hour and watch the money tick in the notch | 1.1.0 |
| [**Una Nota**](una-nota) | Reminders on the notch: a day, a title, a color | 1.0.0 |
| [**K\*llTree**](killtree) | Close an app with every helper it leaves behind | 1.0.0 |

## Brightnesss

One dial for the built-in display that goes further than the brightness keys.

- **XDR.** Past 100% the desktop is pushed into the panel's HDR headroom, up to what the panel allows. It turns itself off on battery or when the Mac runs hot.
- **Dimming.** Below 0% the picture dims past the backlight's minimum, while Droppy stays bright on top.
- **On the shelf.** Swipe over it with two fingers, drag it, click a tick or pinch it open. Night Shift and True Tone sit beside the dial.
- **Keys.** With Accessibility allowed, the brightness keys carry on past both ends.

## Freelancy

Time and money for hourly work, on the shelf.

- **Projects** with an hourly rate and a currency; start and pause sessions from the shelf.
- **On the notch.** While a session runs, its time and the amount earned sit beside the notch.
- **Analytics** over two weeks of time and money, and any project's sessions exported to CSV.

## Una Nota

Reminders and nothing else.

- **A day** on three wheels, a title, a note and a color on the line.
- **On the shelf** they wait in a list; on the day each one shows up on the notch once.
- **Done** from the list or from its own page.

## K\*llTree

Quitting Photoshop, Figma or Zoom leaves helpers running. K\*llTree finds them and closes the whole family.

- **Grouped by developer** under the app you know, by signature, bundle, launchd jobs and parents. Open a row to see every process and what each one does.
- **Hold to Kill.** Apps quit politely, their launchd jobs are taken out so nothing starts them again, and whatever is left is ended.
- **Kept closed** until you open the app again, even after a restart; then everything comes back on its own.
- **Terminals and servers.** Claude Code sessions, dev servers and Homebrew services, each closable on its own.

## Install

1. Download the droplets from the [latest release](https://github.com/prewue/8lx-droplets/releases/latest) and unzip them.
2. Open them in Droppy:
   - **[Droppy Playground](https://getdroppy.app/download/playground)**, free: drop a `.droplet` on its Droplet Store page. It loads unsigned droplets without asking.
   - **Droppy 15.3 or later:** Settings → Store → Local droplets, then approve the build. Droppy asks again each time it opens, because these builds are not signed by the Store.

## Build from source

You need macOS 14 or later, Xcode 26 and the DroppyKit SDK next to this repository.

```sh
git clone https://github.com/prewue/8lx-droplets.git
git clone https://gitlab.com/droppyformac1/droppykit.git

cd 8lx-droplets/killtree
../../droppykit/Scripts/droppykit build      # writes .build/KillTree.droplet
../../droppykit/Scripts/droppykit validate   # the Store's own checks
../../droppykit/Scripts/droppykit run        # the harness: every surface, with made-up data
```

The same three commands work in every droplet's folder. Always build with `droppykit build`: a plain `swift build` folds a second copy of DroppyKit into the bundle, which loads in the harness and fails inside Droppy.

## Repository

```
brightnesss/   Brightnesss
freelancy/     Freelancy
una-nota/      Una Nota
killtree/      K*llTree, with Tools/LensTuner for its tab lens
```

Every folder keeps its own history, carried over from the droplet's own repository.

## License

[MIT](LICENSE) © 2026 8lx. The droplets' icons in this repository are placeholders; the Store's icons are drawn by Droppy.
