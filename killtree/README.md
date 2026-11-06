# K*llTree

Quitting Photoshop, Figma or Zoom leaves helpers running: updaters, sync agents, brokers, often started again by launchd the moment they exit. K*llTree finds them and closes the whole family.

## How to use it

Open K*llTree on the shelf. It has three lists:

- **Apps.** Every process grouped by the developer that signed it, under the app you know. Open a row to see every process and what each one does.
- **Terminals.** Command-line tools and their sessions, such as Claude Code and Codex.
- **Servers.** Dev servers, Homebrew services and scripts left running, with their ports.

Press a row's red button, then hold **Hold to kill**. Apps quit the normal way, and an app with unsaved work stays open. Their launchd jobs are taken out, and whatever is left is ended. **Restore** brings them back.

## The panel

The button in the corner of a list opens a panel for that list.

- **Apps:** show every app, keep them closed, and hold **Close leftovers** to end what is left of apps you already quit. Open apps and menu bar apps stay.
- **Terminals:** keep awake, lid closed mode, and hold **Close all** to end every session in the list, including the one you may be working in.
- **Servers:** include launchd services or not, stay stopped after a restart, and hold **Stop all**.

A dot on the button shows that the Mac is being kept awake: green for keep awake, orange for lid closed mode.

Beside other widgets, K*llTree only offers to open itself alone on the shelf.

## Lid closed mode

It turns off sleep for the whole Mac through `pmset disablesleep`, and by default asks for an administrator password to turn on and to turn off. It stays on after a restart, and after K*llTree is switched off, until you turn it off. K*llTree cannot be removed while it is on. To switch it without a password, turn on "Switch it without a password" in the settings: it asks for your password once, to add a system rule in `/etc/sudoers.d` that allows only this switch. Turning the setting off removes the rule, and K*llTree cannot be removed while the rule is there. A Mac that does not sleep with its lid closed gets warm and drains its battery: do not leave it in a bag.

## Settings

"Keep closed after a restart" and "Close again if they come back" start off. "Also stop system services" asks for an administrator password each time.

## Build

You need macOS 14 or later, Xcode 26 and the DroppyKit SDK.

```sh
droppykit build
droppykit validate
droppykit run
```

## Credits

The tab lens and the progressive blur use Core Animation's own filters, looked up at run time, after UIKit's and Craft's. No code of theirs is copied.

## License

MIT
