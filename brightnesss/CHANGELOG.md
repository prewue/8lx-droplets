# Changelog

## [1.0.1] - 2026-11-06

- Fixed the sun jumping to 100% while XDR is off on battery or from heat: it is now disabled and says why.
- Fixed the brightness keys starting up, or the dimming coming back, after the droplet was switched off.
- Fixed a held brightness key switching the backlight off at the minimum instead of going on into dimming.
- Fixed macOS's own brightness HUD showing when a held key crossed back into the panel's range.
- The welcome screen now shows the droplet's own orb, in its violet.
- Fixed the first opening beside other widgets stretching the whole row to the welcome screen's height.
- The brightness keys now wait on a thread of their own, not on what Droppy is drawing.
- Brightnesss now watches the panel only while the shelf is open, the keys are armed, or XDR or dimming is on.
- In a row, the controls are larger and the dial sits on the row's bottom line.

## [1.0.0] - 2026-10-15

The first release in the Store.

- Added one dial for the built-in display, from dimming below the panel's minimum to XDR past 100%, moved by a two-finger swipe over the shelf, a drag with momentum, a click on a tick, a pinch, or the arrow keys through VoiceOver.
- Added XDR past 100% on a Liquid Retina XDR display, the whole desktop brightened into the panel's HDR headroom; the sun jumps to full XDR and back.
- Added dimming below 0% with Droppy itself staying bright on top, and out of screenshots and recordings.
- Added Night Shift and True Tone beside the dial, lit while on.
- Added the brightness keys carrying on past the panel's ends, with the level on a notch strip, once Droppy has Accessibility.
- Added XDR turning itself off on battery or when the Mac runs hot, each optional in Settings.
