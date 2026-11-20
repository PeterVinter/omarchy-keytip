<div align="center">

# Keytip

**Shows the shortcut for every app you open. No shortcut? Pick a free one and Keytip adds it.**

<img src="https://img.shields.io/badge/Omarchy-4.x-a855f7?style=flat-square" alt="Omarchy 4.x">
<img src="https://img.shields.io/badge/license-MIT-64748b?style=flat-square" alt="MIT">

<br><br>

<img src="preview.png" alt="Keytip's three cards in three Omarchy themes: the shortcut that launches Chromium, three free combinations offered for an app without one, and the confirmation after one is added" width="900">

</div>

## Why you will want it

- **You learn by doing.** The shortcut appears the moment the app opens, not in a cheat sheet you never read.
- **It fills the gaps.** An app without a shortcut gets up to three free combinations, checked against every binding in your Hyprland config.
- **It stays out of the way.** A small card in the corner that never takes focus, shown at most once an hour per app. "Don't ask for this app" is permanent.
- **It looks like Omarchy.** Colors, font and corners follow your theme, dark or light.
- **It is careful with your config.** Keytip writes to `bindings.lua` only when you click, with a backup, a check that the key is free in the running Hyprland, and a rollback if Hyprland rejects the binding or does not answer.

## What it does

| | | |
|---|---|---|
| **The app has a shortcut.** The card names it for 3.5 seconds and fades out. It cannot be clicked and never takes focus. | **The app has none.** The card suggests up to three combinations that are not bound to anything, and waits 12 seconds for a click. | **You click one.** The card confirms the new shortcut, and it works at once. |
| ![Card showing the shortcuts that launch Chromium](docs/screenshots/01-shortcut-known.png) | ![Card suggesting free combinations for an app without a shortcut](docs/screenshots/02-suggest-free-combinations.png) | ![Card confirming that a shortcut was added](docs/screenshots/03-shortcut-added.png) |

- Appears in the bottom corner of the focused monitor and fades out on its own.
- Follows the current Omarchy theme: colors, font, corner radius and spacing.
- Suggestions prefer `SUPER + SHIFT +` a letter from the app's name, where Omarchy keeps its app launchers, and are checked against every binding in your Hyprland config.
- A line along the bottom of the card shows the time left to choose. Hovering the card pauses it.
- Understands Omarchy's launchers: default browser, terminal and editor, web apps, TUIs and `launch-or-focus` bindings.
- Quiet by design:
  - the same app's shortcut is shown at most once an hour;
  - the offer to add a shortcut is made once per app per session;
  - **Don't ask for this app** turns the offer off for that app for good;
  - only apps with an entry in the app launcher get the offer, so dialogs and helper windows do not.
- English and Swedish. It follows the language set under Setup > Language.

## Install

```bash
omarchy plugin add https://github.com/PeterVinter/omarchy-keytip.git --enable --yes
```

Keytip then runs in the background. Preview the card without opening an app:

```bash
omarchy-shell keytip show chromium    # an app with a shortcut
omarchy-shell keytip show mpv         # an app without one
omarchy-shell keytip forget           # ask again for apps you dismissed
```

The argument is a window class, as listed by `hyprctl clients`.

## Remove

```bash
omarchy plugin remove peter.keytip
```

That deletes the plugin folder in `~/.config/omarchy/plugins/`. Two things are left for you to decide on:

- Shortcuts you added stay in `~/.config/hypr/bindings.lua`. Each one sits under a comment ending in `(added by Keytip)`; delete those lines to remove them.
- `~/.local/state/peter.keytip/` holds the list of apps you chose not to be asked about and the last backup of `bindings.lua`. Delete the folder to clear both.

## What it changes on your system

Keytip writes to your configuration only when you click a suggested combination. It then:

1. copies `~/.config/hypr/bindings.lua` to `~/.local/state/peter.keytip/bindings.lua.before`;
2. appends one binding to the end of `bindings.lua`:

   ```lua
   -- Media Player (added by Keytip)
   o.bind("SUPER + SHIFT + D", "Media Player", { launch = "mpv --player-operation-mode=pseudo-gui --" })
   ```

3. runs `hyprctl reload`, and restores the backup if the reload fails, Hyprland reports a config error or does not answer, or the new binding does not become active. Before step 1 it checks `hyprctl binds` and refuses a key that is already bound.

Nothing else is written outside `~/.local/state/peter.keytip/`. Keytip uses no network and needs no root.

To find shortcuts it loads `~/.config/hypr/hyprland.lua` in a separate `lua` process against a stand-in for Hyprland's API and records the bindings it makes. Hyprland itself does not report what a Lua binding launches, so the config is the only source. This runs your Hyprland config as Lua each time an app window opens (about 50 ms), with a time limit, in a sandbox: the config can read files and environment variables, but it cannot start programs, write or delete files, or load native modules. The only shell commands that run are the three read-only questions Omarchy's own config asks (the dictation backend, the cursor theme and the `*.lua` files of a directory); any other command gets an empty answer. If the config stops early, Keytip still shows known shortcuts but does not offer new ones, because the free combinations could already be taken.

## Requirements

- Omarchy 4.x with the Lua Hyprland config.
- `lua`, `hyprctl`, `jq` and `bash`, all part of a standard Omarchy install.

## Settings

The timings are constants at the top of `Service.qml`:

| Constant | Default | Meaning |
|---|---|---|
| `knownMs` | `3500` | How long a known shortcut is shown |
| `askMs` | `12000` | How long the card waits for a choice |
| `resultMs` | `3000` | How long the confirmation is shown |
| `knownCooldownMinutes` | `60` | Minimum time between hints for the same app |

## Development

Logic lives in `Model.js` and is tested without a GUI:

```bash
node test/model.test.js
bash test/scripts.test.sh   # scan sandbox and add-binding, against a fake hyprctl
```

`scan-binds` prints the bindings Keytip sees, one per line, which is the quickest way to check why an app is or is not matched.

## License

MIT. See [LICENSE](LICENSE).
