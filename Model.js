.pragma library

// Pure logic for Keytip: reading the bind scan, matching a window to
// the binds that launch it, and proposing free combinations. No QML types, so
// test/model.test.js can run it under node.

var SHIFT = 1, CTRL = 4, ALT = 8, SUPER = 64

var MAX_NAME = 60
var MAX_COMMAND = 400

// Scan output: "A\t<alias>\t<class>" and "B\t<modmask>\t<key>\t<description>\t<command>".
function parseScan(text) {
  var scan = { binds: [], aliases: {} }
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length && i < 5000; i++) {
    var f = lines[i].split("\t")
    if (f[0] === "A" && f.length >= 3) {
      scan.aliases[f[1]] = f[2].toLowerCase()
    } else if (f[0] === "B" && f.length >= 3) {
      var mods = parseInt(f[1], 10)
      if (!isFinite(mods) || !f[2]) continue
      scan.binds.push({ mods: mods, key: f[2], desc: f[3] || "", cmd: f[4] || "" })
    }
  }
  return scan
}

// Minimal POSIX-ish word splitting: enough for the commands o.bind produces.
function shellWords(command) {
  var words = [], word = "", quote = "", has = false
  var s = String(command || "")
  for (var i = 0; i < s.length; i++) {
    var c = s.charAt(i)
    if (quote === "'") {
      if (c === "'") quote = ""; else word += c
    } else if (quote === '"') {
      if (c === '"') quote = ""
      else if (c === "\\" && i + 1 < s.length) word += s.charAt(++i)
      else word += c
    } else if (c === "'" || c === '"') {
      quote = c; has = true
    } else if (c === "\\" && i + 1 < s.length) {
      word += s.charAt(++i); has = true
    } else if (c === " " || c === "\t") {
      if (has || word !== "") words.push(word)
      word = ""; has = false
    } else {
      word += c
    }
  }
  if (has || word !== "") words.push(word)
  return words
}

function basename(path) {
  return String(path || "").replace(/\/+$/, "").split("/").pop()
}

// "https://app.hey.com/calendar/weeks/" -> { host: "app.hey.com", key: "app.hey.com__calendar_weeks_" }
// which is how Chromium names an --app window: chrome-<key>-<Profile>.
function webTarget(url) {
  var m = String(url || "").match(/^https?:\/\/([^\/?#]+)([^?#]*)/i)
  if (!m) return null
  var host = m[1].toLowerCase()
  var path = m[2].replace(/^\//, "").replace(/\//g, "_")
  return { host: host, key: (host + "__" + path).toLowerCase() }
}

function windowWebKey(cls) {
  var m = String(cls || "").toLowerCase().match(/^(?:chrome|chromium|brave|msedge|vivaldi|opera|helium)-(.+__.*)-[^-]+$/)
  return m ? m[1] : ""
}

var LAUNCH_ALIASES = { nautilus: "org.gnome.nautilus" }

// What a bind's command opens: window classes and/or web app targets.
function targetsFor(command, aliases, depth) {
  var out = { classes: [], web: [] }
  var words = shellWords(command)
  while (words.length && (words[0] === "exec" || words[0] === "setsid" || words[0] === "uwsm-app" || words[0] === "--")) words.shift()
  if (!words.length) return out

  var prog = basename(words[0]).toLowerCase()
  var args = words.slice(1)

  if (prog === "omarchy-launch-or-focus") {
    if (args[0]) out.classes.push(args[0].replace(/\\b|[\^$]/g, "").toLowerCase())
    if (args[1] && !(depth > 2)) {
      var inner = targetsFor(args[1], aliases, (depth || 0) + 1)
      out.classes = out.classes.concat(inner.classes)
      out.web = out.web.concat(inner.web)
    }
  } else if (prog === "omarchy-launch-webapp" || prog === "omarchy-launch-or-focus-webapp") {
    var web = webTarget(prog === "omarchy-launch-webapp" ? args[0] : args[1])
    if (web) out.web.push(web)
  } else if (prog === "omarchy-launch-tui" || prog === "omarchy-launch-or-focus-tui") {
    if (args[0] && args[0].indexOf("--app-id=") === 0) out.classes.push(args[0].slice(9).toLowerCase())
    else if (args[0]) out.classes.push("org.omarchy." + basename(args[0]).toLowerCase())
  } else if (prog.indexOf("omarchy-launch-") === 0) {
    // Variants with flags (browser --private) open something else than the app itself.
    if (args.length) return out
    var what = prog.slice("omarchy-launch-".length)
    var alias = (aliases && aliases[what]) || LAUNCH_ALIASES[what] || what
    out.classes.push(String(alias).toLowerCase())
  } else {
    // "ghostty -e yazi" opens yazi, not a plain ghostty: no class to match.
    for (var i = 0; i < args.length; i++) {
      if (args[i] === "-e" || args[i] === "-x" || args[i] === "--command") return out
    }
    out.classes.push(prog)
  }
  return out
}

// Names a window may go by: its class, the class's last segment
// (org.gnome.Nautilus -> nautilus), its desktop id and its executable.
function windowKeys(cls, desktopId, exec) {
  var keys = [], seen = {}
  function add(value) {
    var v = String(value || "").toLowerCase()
    if (v && !seen[v]) { seen[v] = true; keys.push(v) }
  }
  add(cls)
  add(String(cls || "").split(".").pop())
  add(String(desktopId || "").replace(/\.desktop$/i, ""))
  add(basename(exec))
  return keys
}

// The binds that launch this window, best matches only, at most `limit`.
function matchBinds(scan, cls, desktopId, exec, limit) {
  var keys = windowKeys(cls, desktopId, exec)
  var webKey = windowWebKey(cls)
  var webHost = webKey ? webKey.split("__")[0] : ""
  var scored = [], best = 0

  for (var i = 0; i < scan.binds.length; i++) {
    var bind = scan.binds[i]
    if (!bind.cmd || bind.mods === 0) continue
    var targets = targetsFor(bind.cmd, scan.aliases)
    var score = 0
    if (webKey) {
      // A web app window is only ever matched as a web app, never as "chromium".
      for (var w = 0; w < targets.web.length; w++) {
        if (targets.web[w].key === webKey) score = Math.max(score, 3)
        else if (targets.web[w].host === webHost) score = Math.max(score, 1)
      }
    } else {
      for (var c = 0; c < targets.classes.length; c++) {
        if (keys.indexOf(targets.classes[c]) !== -1) score = Math.max(score, 2)
      }
    }
    if (score > 0) { scored.push({ bind: bind, score: score }); best = Math.max(best, score) }
  }

  var out = []
  for (var j = 0; j < scored.length && out.length < (limit || 2); j++) {
    if (scored[j].score === best) out.push(scored[j].bind)
  }
  return out
}

var CODE_KEYS = { 10: "1", 11: "2", 12: "3", 13: "4", 14: "5", 15: "6", 16: "7", 17: "8", 18: "9", 19: "0" }

function keyLabel(key) {
  var k = String(key || "")
  var code = k.match(/^code:(\d+)$/i)
  if (code) return CODE_KEYS[code[1]] || k
  return k.toUpperCase()
}

function modNames(mods) {
  var names = []
  if (mods & SUPER) names.push("SUPER")
  if (mods & SHIFT) names.push("SHIFT")
  if (mods & CTRL) names.push("CTRL")
  if (mods & ALT) names.push("ALT")
  return names
}

// ["SUPER", "SHIFT", "B"]: one entry per keycap.
function keycaps(mods, key) {
  return modNames(mods).concat([keyLabel(key)])
}

// "SUPER + SHIFT + B": the form o.bind takes.
function bindKeys(mods, key) {
  return keycaps(mods, key).join(" + ")
}

function nameLetters(name) {
  var folded = String(name || "").normalize("NFD").replace(/[̀-ͯ]/g, "").toUpperCase()
  var letters = [], seen = {}
  for (var i = 0; i < folded.length; i++) {
    var c = folded.charAt(i)
    if (c >= "A" && c <= "Z" && !seen[c]) { seen[c] = true; letters.push(c) }
  }
  return letters
}

// Up to `limit` unbound combinations, preferring the app's own letters (its
// initial first) on SUPER SHIFT, where Omarchy keeps its app launchers.
function suggest(scan, name, limit) {
  var used = {}
  for (var i = 0; i < scan.binds.length; i++) {
    used[scan.binds[i].mods + ":" + keyLabel(scan.binds[i].key)] = true
  }
  var letters = nameLetters(name)
  var layers = [SUPER | SHIFT, SUPER | SHIFT | ALT, SUPER | ALT]
  var perLayer = [2, 1, 1]
  var out = []
  var max = limit || 3
  for (var l = 0; l < layers.length && out.length < max; l++) {
    var taken = 0
    for (var j = 0; j < letters.length && taken < perLayer[l] && out.length < max; j++) {
      if (used[layers[l] + ":" + letters[j]]) continue
      out.push({ mods: layers[l], key: letters[j] })
      taken++
    }
  }
  return out
}

function shellQuote(word) {
  var w = String(word)
  return /^[A-Za-z0-9_@%+=:,.\/-]+$/.test(w) ? w : "'" + w.replace(/'/g, "'\\''") + "'"
}

// The command a desktop entry runs, minus its %f/%U style field codes.
// Returns "" when there is nothing safe to bind.
function launchCommand(argv, execString) {
  var words = argv && argv.length ? Array.prototype.slice.call(argv) : shellWords(execString)
  var kept = []
  for (var i = 0; i < words.length; i++) {
    var w = String(words[i])
    if (/^%[a-zA-Z]$/.test(w)) continue
    kept.push(shellQuote(w.replace(/%[a-zA-Z]/g, "")))
  }
  var command = kept.join(" ")
  if (!command || command.length > MAX_COMMAND || /[\x00-\x1f\x7f]/.test(command)) return ""
  return command
}

// Display names come from desktop files and window classes: bound and
// stripped of control characters before they are shown or written anywhere.
function cleanName(name) {
  return String(name || "").replace(/[\x00-\x1f\x7f]/g, " ").replace(/\s+/g, " ").trim().slice(0, MAX_NAME)
}

if (typeof module !== "undefined") {
  module.exports = {
    parseScan: parseScan, shellWords: shellWords, webTarget: webTarget, windowWebKey: windowWebKey,
    targetsFor: targetsFor, windowKeys: windowKeys, matchBinds: matchBinds, keycaps: keycaps,
    bindKeys: bindKeys, nameLetters: nameLetters, suggest: suggest, launchCommand: launchCommand,
    cleanName: cleanName
  }
}
