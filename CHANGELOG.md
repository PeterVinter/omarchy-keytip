# Changelog

## 1.0.2

Fixes the three Low findings from the review of 1.0.1.

- **The config scan runs in a sandbox.** `scan.lua` still runs your Hyprland Lua config to read the bindings, but the config can no longer start programs (`os.execute`, `io.popen`), write or delete files, or load native modules. The only shell commands that run are the three read-only questions Omarchy's own config asks (dictation backend, cursor theme, the `*.lua` files of a directory); any other command gets an empty answer. Before, a config or module that did work at load time repeated it on every window open (a Superwhisper integration started its shortcut bridge on each scan).
- **A truncated scan is never taken for a complete one.** The scan now ends with `E ok` when it reached the end of the config, and `E partial` when it stopped early (config error, time limit, no `lua`). On an incomplete scan Keytip still shows known shortcuts but offers no new combinations. `add-binding` no longer relies on the scan at all: it asks the running Hyprland (`hyprctl binds`) whether the key is bound, and also checks the file, case-insensitively.
- **`add-binding` no longer reports success it did not verify.** It restores `bindings.lua` if the reload fails, if Hyprland's config errors cannot be read, if they are not empty, or if the new binding is not live in Hyprland afterwards. If Hyprland does not answer at all, it refuses before writing anything. `jq` is now needed (part of Omarchy).
- Tests: `test/scripts.test.sh` runs the sandbox and `add-binding` against a temporary home and a fake `hyprctl`; `test/model.test.js` covers the new `complete` flag.

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
