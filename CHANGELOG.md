# Changelog

## 1.0.1

Listing and documentation only; the plugin's behavior is unchanged.

- **A short description.** The manifest description, shown on the marketplace card, is one sentence: "Shows the shortcut for every app you open. No shortcut? Pick a free one and Keytip adds it."
- **A new preview image and a third screenshot.** The preview is now a 1920x1080 poster with the three cards (known shortcut, free suggestions, confirmation) in three Omarchy themes. The gallery has a new `03-shortcut-added.png`. The cards are real captures of the plugin; the confirmation card was triggered with a temporary demo call so that no binding was written.
- **README first screen.** A one-line pitch, the new image, and a short "Why you will want it" list before the details.

## 1.0.0

First release.

- Shows the shortcut that launches an app when its window opens, then fades out.
- Suggests up to three free combinations for apps without a shortcut and adds the chosen one to `~/.config/hypr/bindings.lua`, with a backup and a rollback if Hyprland rejects it.
- Matches Omarchy's launchers: default browser, terminal and editor, web apps, TUIs and `launch-or-focus` bindings.
- Per-app cooldown, once-per-session offers and a permanent "Don't ask for this app".
- English and Swedish.
