# Daylight

Daylight is a native Mac background studio powered by Apple Intelligence. Use an existing image as your background, transform it privately, or create an abstract wallpaper from words, then apply it behind an optional live Apple Calendar overlay.

## Build

```sh
chmod +x scripts/build-app.sh
./scripts/build-app.sh
open outputs/Daylight.app
```

The first time you connect Apple Calendar, macOS asks for full calendar access. Daylight needs read access to show events and write access to create, edit, and delete them. Its network access is limited to the signed GitHub release feed used for updates.

## Interaction

- Choose **Create Background…** from the menu bar, or press **Command–B** while the calendar is interactive.
- Describe any background and choose **Generate with Image Playground**. On macOS 27, Apple’s supported system sheet creates the image and returns the approved result to Daylight.
- Choose an image to make it the base background. Reimagine it in Image Playground, use it unchanged, or apply quick private tone, brightness, contrast, saturation, monochrome, warmth, and blur edits.
- Add up to eight images, PDFs, text, RTF, or JSON references. The first image is always clearly labeled as the base image.
- Apple discontinued hidden Image Playground generation on macOS 27. Daylight uses Apple’s required system sheet for full generation and keeps separate local-only shortcuts for fast edits.
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
