# Changelog

## [1.1.0] - 2026-11-06

- Added a button in the corner of every list that opens a panel of its own.
- Apps: show every app, keep them closed, and close leftovers, which ends what is left of apps you already quit and leaves open apps alone.
- Terminals: keep the Mac awake, also with the lid closed, and close all. Lid closed mode can switch without a password, through a system rule you add in the settings.
- Servers: include launchd services or not, keep services stopped after a restart, and stop all.
- A dot on the corner button shows that the Mac is being kept awake: green for keep awake, orange for lid closed mode.
- Beside other widgets, K*llTree now says it can only be used on its own, with a button that opens it alone on the shelf.
- The welcome screen now shows the K*ll logo.
- Closing a process no longer ends unrelated copies of the same executable.
- Restore keeps its record until it has worked, and gives a job back as it was: what you had disabled stays disabled.
- A state file that cannot be read is kept aside instead of being overwritten.
- A process row now does what its note says: an app quits the normal way, and a job leaves launchd until the next login.
- A job launchd refuses to stop now says "Could not stop".
- The Servers list no longer shows helpers of apps without a port, or what another program started. Other people's processes on a shared Mac are no longer listed, and neither is Droppy.
- "Keep closed after a restart" and "Close again if they come back" now start off. A setting you already changed stays as it is.
- K*llTree now scans only while its widget is open, or while something closed has to be watched.

## [1.0.0] - 2026-10-24

- Added a shelf widget that groups every process by the developer that signed it, under the app you know.
- Added closing an app with its helpers and launchd jobs in one hold, with Restore to bring them back.
- Added lists for command-line tools in terminals and for servers and Homebrew services.
