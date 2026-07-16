<!-- sparkle-sign-warning:
IMPORTANT: This file was signed by Sparkle. Any modifications to this file requires updating signatures in appcasts that reference this file! This will involve re-running generate_appcast or sign_update.
-->
# Daylight 1.4.1

- Makes Launch at Login reliable on macOS beta builds where the native login-item service reports itself unavailable.
- Keeps the native macOS login-item path as the first choice and automatically uses a user LaunchAgent only when needed.
- Keeps intentional Quit behavior predictable; Daylight starts again at sign-in, not immediately after you quit.
