// Run: node test/model.test.js
const fs = require("fs")
const path = require("path")
const assert = require("assert")

const source = fs.readFileSync(path.join(__dirname, "..", "Model.js"), "utf8").replace(/^\.pragma library$/m, "")
const mod = { exports: {} }
new Function("module", source)(mod)
const M = mod.exports

const scan = M.parseScan([
  "A\tbrowser\tchromium",
  "A\tterminal\tcom.mitchellh.ghostty",
  "A\teditor\tcode",
  "B\t64\tRETURN\tTerminal\tomarchy-launch-terminal",
  "B\t65\tRETURN\tBrowser\tomarchy-launch-browser",
  "B\t65\tB\tBrowser\tomarchy-launch-browser",
  "B\t73\tB\tBrowser (private)\tomarchy-launch-browser --private",
  "B\t65\tF\tFile manager\tomarchy-launch-nautilus",
  "B\t65\tN\tEditor\tomarchy-launch-editor",
  "B\t65\tQ\tCalculator\tomacalc",
  "B\t0\tXF86Calculator\tCalculator\tomacalc",
  "B\t65\tO\tObsidian\tomarchy-launch-or-focus '^obsidian$' 'uwsm-app -- obsidian'",
  "B\t65\tT\tActivity\tomarchy-launch-tui 'btop'",
  "B\t65\tC\tCalendar\tomarchy-launch-webapp 'https://app.hey.com/calendar/weeks/'",
  "B\t65\tE\tEmail\tomarchy-launch-webapp 'https://app.hey.com'",
  "B\t65\tY\tYouTube\tomarchy-launch-webapp 'https://youtube.com/'",
  "B\t73\tG\tWhatsApp\tomarchy-launch-or-focus-webapp 'WhatsApp' 'https://web.whatsapp.com/'",
  "B\t64\tY\tYazi\tuwsm-app -- ghostty -e yazi",
  "B\t64\tcode:10\tSwitch to workspace 1\t",
  "B\t64\tW\tClose window\t",
  "garbage line",
].join("\n"))

const descs = (cls, id, exec) => M.matchBinds(scan, cls, id, exec, 2).map(b => b.desc + "=" + M.bindKeys(b.mods, b.key))

assert.strictEqual(scan.binds.length, 17)

// Class matches, through aliases, class tails and focus patterns.
assert.deepStrictEqual(descs("chromium"), ["Browser=SUPER + SHIFT + RETURN", "Browser=SUPER + SHIFT + B"])
assert.deepStrictEqual(descs("org.gnome.Nautilus"), ["File manager=SUPER + SHIFT + F"])
assert.deepStrictEqual(descs("com.mitchellh.ghostty"), ["Terminal=SUPER + RETURN"])
assert.deepStrictEqual(descs("obsidian"), ["Obsidian=SUPER + SHIFT + O"])
assert.deepStrictEqual(descs("Code", "code.desktop"), ["Editor=SUPER + SHIFT + N"])
assert.deepStrictEqual(descs("org.omarchy.btop"), ["Activity=SUPER + SHIFT + T"])
// Binds without modifiers are not hinted; the modified one is.
assert.deepStrictEqual(descs("omacalc"), ["Calculator=SUPER + SHIFT + Q"])
// Matched through the desktop entry's executable when the class differs.
assert.deepStrictEqual(descs("Some.Odd.Class", "", "/usr/bin/omacalc"), ["Calculator=SUPER + SHIFT + Q"])
assert.deepStrictEqual(descs("mpv"), [])

// Web apps: exact path beats same-host, and never match the browser's binds.
assert.deepStrictEqual(descs("chrome-youtube.com__-Default"), ["YouTube=SUPER + SHIFT + Y"])
assert.deepStrictEqual(descs("chrome-app.hey.com__-Default"), ["Email=SUPER + SHIFT + E"])
assert.deepStrictEqual(descs("chrome-app.hey.com__calendar_weeks_-Default"), ["Calendar=SUPER + SHIFT + C"])
assert.deepStrictEqual(descs("chrome-web.whatsapp.com__-Default"), ["WhatsApp=SUPER + SHIFT + ALT + G"])
assert.deepStrictEqual(descs("chrome-discord.com__channels_@me-Default"), [])
assert.deepStrictEqual(descs("brave-youtube.com__-Default"), ["YouTube=SUPER + SHIFT + Y"])

// Suggestions are free, prefer the app's letters, initial first.
const combos = name => M.suggest(scan, name, 3).map(c => M.bindKeys(c.mods, c.key))
assert.deepStrictEqual(combos("mpv"), ["SUPER + SHIFT + M", "SUPER + SHIFT + P", "SUPER + SHIFT + ALT + M"])
// B, O, C, E, Y... are taken on SUPER SHIFT; B is taken on SUPER SHIFT ALT too.
assert.deepStrictEqual(combos("Boy"), ["SUPER + SHIFT + ALT + O", "SUPER + ALT + B"])
assert.deepStrictEqual(combos("Ölands"), ["SUPER + SHIFT + L", "SUPER + SHIFT + A", "SUPER + SHIFT + ALT + O"])
for (const c of M.suggest(scan, "Obsidian Notes", 3)) {
  assert.ok(!scan.binds.some(b => b.mods === c.mods && b.key.toUpperCase() === c.key))
}
assert.deepStrictEqual(combos("1234"), [])

// Commands and names from desktop files are bounded and quoted.
assert.strictEqual(M.launchCommand(["mpv", "--player-operation-mode=pseudo-gui", "--", "%U"]), "mpv --player-operation-mode=pseudo-gui --")
assert.strictEqual(M.launchCommand(null, "omarchy-launch-webapp https://discord.com/channels/@me"), "omarchy-launch-webapp https://discord.com/channels/@me")
assert.strictEqual(M.launchCommand(["my app", "it's"]), "'my app' 'it'\\''s'")
assert.strictEqual(M.launchCommand(["a\nb"]), "")
assert.strictEqual(M.launchCommand(["x".repeat(500)]), "")
assert.strictEqual(M.launchCommand([]), "")
assert.strictEqual(M.cleanName("  <img src=x>\n\tApp  "), "<img src=x> App")
assert.strictEqual(M.cleanName("n".repeat(200)).length, 60)

assert.deepStrictEqual(M.keycaps(77, "code:10"), ["SUPER", "SHIFT", "CTRL", "ALT", "1"])
assert.deepStrictEqual(M.shellWords(`a 'b c' "d \\" e" f\\ g ''`), ["a", "b c", 'd " e', "f g", ""])

console.log("ok")
