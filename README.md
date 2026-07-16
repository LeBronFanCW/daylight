# Daylight

Daylight is a native Mac background studio powered by Apple Intelligence. Describe the background you want, add images or files for inspiration, create it with Apple Foundation Models and Image Playground, then apply it behind an optional live Apple Calendar overlay.

## Build

```sh
chmod +x scripts/build-app.sh
./scripts/build-app.sh
open outputs/Daylight.app
```

The first time you connect Apple Calendar, macOS asks for full calendar access. Daylight needs read access to show events and write access to create, edit, and delete them. Its network access is limited to the signed GitHub release feed used for updates.

## Interaction

- Choose **Create Background…** from the menu bar, or press **Command–B** while the calendar is interactive.
- Add up to eight images, PDFs, text, RTF, or JSON references and describe the result you want.
- Foundation Models turns your request and file notes into an art-directed concept. On macOS 26, Daylight can route it to Image Playground in the background; on macOS 27, where Apple removed that hidden API, Daylight renders the concept privately inside the app and can incorporate your image references.
- Preview the result, then choose **Apply Background** to use it on the desktop and Lock Screen.
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

To open the background studio immediately while developing:

```sh
open outputs/Daylight.app --args --studio
```
