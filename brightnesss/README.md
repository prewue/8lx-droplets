# Brightnesss

XDR past 100% and dimming below zero, from the notch.

Brightnesss is a Droplet for [Droppy](https://getdroppy.app), the Dynamic Island
and shelf for Mac. It gives the built-in display one dial that goes further than
the brightness keys do: past 100% it pushes an XDR display into its HDR headroom,
so the whole desktop gets brighter in the sun; below 0% it dims the picture past
the backlight's minimum for a dark room, with Droppy itself staying bright on top.

## What it does

- **Dial.** A ruler of levels under a fixed needle: swipe the trackpad with two
  fingers anywhere over the widget, drag it with momentum, click a tick, or pinch
  to open the light. It snaps onto 0 and 100 when it stops near them, with a tap
  every five levels and a firmer one across a zone.
- **XDR.** Above 100 the desktop is multiplied into the panel's HDR headroom; the
  ceiling is what the panel reports, up to 200%. Click the sun for full XDR and
  back. Costs battery and heat, so it turns itself off on battery or when the
  Mac runs hot, each optional in Settings.
- **Dimming.** Below 0 a black layer under Droppy's own windows takes the picture
  down past the backlight's minimum. The shelf stays bright, and screenshots and
  recordings are not dimmed.
- **Night Shift and True Tone.** Two discs beside the dial, lit while on.
- **Brightness keys.** Inside the panel's range they are the system's. With
  Accessibility granted to Droppy, brightness down at the minimum keeps dimming
  and brightness up at the maximum goes into XDR, with the level on a strip at the
  notch.
- **Settings.** The two XDR guards, the keys past the ends, and the strip.

Only the built-in display, for now.

## How it works

The panel's own brightness goes through DisplayServices. XDR is an invisible
EDR overlay with a multiply filter, the technique [Crisp](https://github.com/didriksg/Crisp)
and BrightIntosh use. Dimming is a black window one level under Droppy's notch
window. Night Shift and True Tone go through CoreBrightness, as Control Center does.

## Building

Needs the [DroppyKit](https://gitlab.com/droppyformac1/droppykit) SDK and Xcode 26 or later.

```bash
droppykit build
droppykit validate
```

Then put `.build/Brightnesss.droplet` into Droppy under Settings, Store, Local
droplets, or into [Droppy Playground](https://getdroppy.app/download/playground).

## License

MIT. See LICENSE.
