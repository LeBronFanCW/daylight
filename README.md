# Daylight

Daylight is a native macOS menu-bar app that places a live, glanceable Apple Calendar at the desktop layer. The calendar stays click-through during normal use and becomes editable from the menu bar or with **Control–Shift–T**.

## Build

```sh
chmod +x scripts/build-app.sh
./scripts/build-app.sh
open outputs/Daylight.app
```

The first time you connect Apple Calendar, macOS asks for full calendar access. Daylight needs read access to show events and write access to create, edit, and delete them. The app is sandboxed; its only network access is the signed GitHub release feed used for updates.

## Interaction

- Click the calendar icon in the menu bar to toggle interactive mode.
- Press **Control–Shift–T** from any app to toggle interactive mode.
- Choose **Week**, **Month**, or **Year** from the interaction toolbar or menu bar.
- Use the arrow controls to move between periods, or choose **Today** to return.
- Switch between the warm **Light** appearance and the original **Dark** appearance; Daylight remembers your choice.
- In interactive mode, click an event to edit it or use **New event**.
- Press Escape or click **Done** to return the calendar to the background.
- Daylight renders a read-only calendar snapshot as your Mac wallpaper so it also appears on the Lock Screen. Event titles are hidden by default; use the **Lock Screen** menu to reveal them, refresh the snapshot, turn the feature off, or restore your previous wallpaper.
- Daylight checks for signed updates once a day and can install them automatically. Use **Check for Updates…** in the menu bar to check immediately.
- Daylight enables **Launch at Login** by default so your calendar returns automatically after signing in or restarting. You can turn it off from the menu bar at any time.

## Preview mode

For a permission-free visual preview:

```sh
open outputs/Daylight.app --args --demo --interactive
```
