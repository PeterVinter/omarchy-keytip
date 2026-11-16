import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// Keytip. When an app's window opens:
//   - it has a launch shortcut: a small card names it for a few seconds;
//   - it has none: the card offers free combinations, and the one clicked is
//     appended to ~/.config/hypr/bindings.lua by ./add-binding.
// The card sits in the bottom corner, never takes keyboard focus, and fades
// out on its own. Colors, font, radius and spacing come from the theme.
Item {
  id: root

  property string omarchyPath: ""
  property var shell: null
  property var manifest: null

  // ---------------------------------------------------------------- tuning

  // How long the card stays (ms) when it only names a shortcut, when it is
  // waiting for a choice, and after a choice was saved.
  readonly property int knownMs: 3500
  readonly property int askMs: 12000
  readonly property int resultMs: 3000
  // The same app's shortcut is not repeated more often than this (minutes).
  readonly property int knownCooldownMinutes: 60

  // ----------------------------------------------------------------- state

  // "known" | "ask" | "saving" | "saved" | "error"
  property string mode: "known"
  property bool opened: false     // drives the fade
  property bool mapped: false     // keeps the surface until the fade is done
  property string appClass: ""
  property string appName: ""
  property string appIcon: ""
  property string launch: ""
  property var binds: []          // [{ caps: [...] }] for "known"
  property var suggestions: []    // [{ mods, key, caps: [...] }] for "ask"
  property string savedKeys: ""

  property string pendingClass: ""
  property bool pendingForced: false
  property var shownAt: ({})      // class -> ms, for the cooldown
  property var askedThisSession: ({})
  property var ignored: ({})      // class -> true, persisted

  readonly property bool interactive: mode === "ask"
  readonly property string here: String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "").replace(/\/+$/, "")
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/peter.keytip"

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  // ------------------------------------------------------------- triggers

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (!event || String(event.name) !== "openwindow") return
      // ADDRESS,WORKSPACE,CLASS,TITLE: the title may hold commas, the class not.
      var parts = String(event.data || "").split(",")
      var cls = parts.length >= 3 ? parts[2] : ""
      if (cls === "" || cls.length > 200) return
      // A choice in progress is not replaced by the next window.
      if (root.opened && root.mode !== "known") return
      root.pendingClass = cls
      root.pendingForced = false
      settle.restart()
    }
  }

  // omarchy-shell keytip show <class>   preview the card for a class
  // omarchy-shell keytip forget         ask again for dismissed apps
  ShellIpc {
    target: "keytip"
    function show(windowClass: string): string {
      root.pendingClass = String(windowClass || "").slice(0, 200)
      root.pendingForced = true
      settle.restart()
      return "ok"
    }
    function forget(): string {
      root.ignored = ({})
      root.askedThisSession = ({})
      ignoredFile.setText("{}\n")
      return "ok"
    }
    function state(): string { return root.opened ? root.mode : "closed" }
  }

  // Lets a burst of windows settle, and the new window draw first.
  Timer {
    id: settle
    interval: 450
    onTriggered: if (root.pendingClass !== "" && !scan.running) scan.running = true
  }

  Process {
    id: scan
    command: [root.here + "/scan-binds"]
    stdout: StdioCollector {
      onStreamFinished: root.decide(Model.parseScan(this.text))
    }
  }

  // ------------------------------------------------------------- deciding

  function decide(result) {
    var cls = pendingClass
    var forced = pendingForced
    pendingClass = ""
    if (cls === "") return
    if (opened && mode !== "known") return

    var entry = DesktopEntries.heuristicLookup(cls)
    var exec = entry && entry.command && entry.command.length ? String(entry.command[0]) : ""
    var matches = Model.matchBinds(result, cls, entry ? entry.id : "", exec, 2)
    var name = Model.cleanName(entry && entry.name ? entry.name : (matches.length ? matches[0].desc : cls))
    var now = Date.now()

    if (matches.length > 0) {
      if (!forced && shownAt[cls] && now - shownAt[cls] < knownCooldownMinutes * 60000) return
      var list = []
      for (var i = 0; i < matches.length; i++) list.push({ caps: Model.keycaps(matches[i].mods, matches[i].key) })
      shownAt[cls] = now
      present("known", cls, name, entry, list, [], "")
      return
    }

    // Only apps the launcher knows get an offer: no nagging for dialogs,
    // helper windows or terminal programs.
    if (!entry || entry.noDisplay || entry.runInTerminal) return
    if (!forced && (ignored[cls] || askedThisSession[cls])) return
    var command = Model.launchCommand(entry.command, entry.execString)
    if (command === "" || name === "") return

    var options = Model.suggest(result, name, 3)
    for (var j = 0; j < options.length; j++) options[j].caps = Model.keycaps(options[j].mods, options[j].key)
    askedThisSession[cls] = true
    present("ask", cls, name, entry, [], options, command)
  }

  function present(nextMode, cls, name, entry, bindList, options, command) {
    mode = nextMode
    appClass = cls
    appName = name
    appIcon = entry && entry.icon ? Quickshell.iconPath(entry.icon, true) : ""
    binds = bindList
    suggestions = options
    launch = command
    unmap.stop()
    mapped = true
    opened = true
    restartTimeout()
  }

  function restartTimeout() {
    hide.interval = mode === "known" ? knownMs : mode === "ask" ? askMs : resultMs
    countdown.stop()
    if (mode === "saving") { hide.stop(); return }
    hide.restart()
    if (mode === "ask") countdown.restart()
  }

  function close() {
    hide.stop()
    countdown.stop()
    opened = false
    unmap.restart()
  }

  Timer { id: hide; onTriggered: root.close() }
  // Longer than the fade, so the surface goes only once it is invisible.
  Timer { id: unmap; interval: 260; onTriggered: if (!root.opened) root.mapped = false }

  // ---------------------------------------------------------------- acting

  function choose(option) {
    if (mode !== "ask" || add.running || launch === "") return
    savedKeys = option.caps.join(" ")
    add.command = [here + "/add-binding", Model.bindKeys(option.mods, option.key), appName, launch]
    mode = "saving"
    restartTimeout()
    add.running = true
  }

  function neverAsk() {
    var next = Util.cloneJson(ignored) || {}
    next[appClass] = true
    ignored = next
    ignoredFile.setText(JSON.stringify(next, null, 2) + "\n")
    close()
  }

  Process {
    id: add
    onExited: function(exitCode) {
      root.mode = exitCode === 0 ? "saved" : "error"
      root.restartTimeout()
    }
  }

  FileView {
    id: ignoredFile
    path: root.stateDir + "/ignored.json"
    printErrors: false
    atomicWrites: true
    onLoaded: {
      try {
        var parsed = JSON.parse(text())
        var clean = {}
        var count = 0
        for (var key in parsed) {
          if (parsed[key] === true && key.length <= 200 && count++ < 500) clean[key] = true
        }
        root.ignored = clean
      } catch (e) {}
    }
  }

  // ------------------------------------------------------------------ card

  readonly property int pad: Style.space(14)
  readonly property int gap: Style.space(10)
  readonly property int iconSize: Style.space(22)
  readonly property color textColor: Commons.Color.popups.text

  component Label: Text {
    textFormat: Text.PlainText
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    color: root.textColor
    elide: Text.ElideRight
    maximumLineCount: 1
  }

  component Keycaps: Row {
    id: caps
    property var keys: []
    spacing: Style.spacing.sm
    Repeater {
      model: caps.keys
      Rectangle {
        required property string modelData
        width: Math.max(height, capText.implicitWidth + Style.spacing.lg * 2)
        height: capText.implicitHeight + Style.spacing.sm * 2
        radius: Math.min(Style.cornerRadius, Style.space(5))
        color: Util.alpha(root.textColor, 0.08)
        border.width: Math.max(1, Style.spacing.hairline)
        border.color: Util.alpha(root.textColor, 0.3)
        Label {
          id: capText
          anchors.centerIn: parent
          text: parent.modelData
          font.pixelSize: Style.font.bodySmall
          font.bold: true
        }
      }
    }
  }

  OverlayWindow {
    id: surface
    shown: root.mapped
    shownKeyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.namespace: "keytip"
    // Only the card takes clicks, and only while it has something to click.
    mask: Region {
      x: card.x
      y: card.y
      width: root.interactive ? card.width : 0
      height: root.interactive ? card.height : 0
    }

    BorderSurface {
      id: card
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.rightMargin: Style.space(24)
      anchors.bottomMargin: Style.space(24)
      width: borderLeft + root.pad + body.implicitWidth + root.pad + borderRight
      height: borderTop + root.pad + body.implicitHeight + root.pad + borderBottom
      color: Util.alpha(Commons.Color.popups.background, 0.97)
      borderSpec: Border.surfaceSpec("popups", "border", Commons.Color.popups.border, Math.max(1, Style.space(2)))
      radius: Style.cornerRadius
      clip: true

      opacity: root.opened ? 1 : 0
      scale: root.opened ? 1 : 0.97
      transformOrigin: Item.BottomRight
      Behavior on opacity {
        NumberAnimation { duration: Style.duration(root.opened ? 180 : 160); easing.type: Easing.OutCubic }
      }
      Behavior on scale {
        NumberAnimation { duration: Style.duration(180); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
      }

      // Reading or aiming at the card holds it open; the clock restarts on leave.
      HoverHandler {
        onHoveredChanged: {
          if (!root.opened || root.mode === "saving") return
          if (hovered) { hide.stop(); countdown.stop(); timeLeft.fraction = 1 }
          else root.restartTimeout()
        }
      }

      Column {
        id: body
        x: card.borderLeft + root.pad
        y: card.borderTop + root.pad
        spacing: root.gap

        // App, and either its shortcut or what is being said about it.
        Row {
          spacing: root.gap

          Image {
            visible: root.appIcon !== ""
            anchors.verticalCenter: parent.verticalCenter
            width: root.iconSize
            height: root.iconSize
            sourceSize.width: root.iconSize * 2
            sourceSize.height: root.iconSize * 2
            source: root.appIcon
            asynchronous: true
          }

          Label {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, Style.space(320))
            font.pixelSize: Style.font.subtitle
            font.bold: root.mode === "known"
            color: root.mode === "error" ? Commons.Color.urgent : root.textColor
            text: root.mode === "known" ? root.appName
              : root.mode === "ask" ? strings.t("ask.title").arg(root.appName)
              : root.mode === "saving" ? strings.t("saving").arg(root.savedKeys)
              : root.mode === "saved" ? strings.t("saved").arg(root.savedKeys).arg(root.appName)
              : strings.t("error")
          }

          Repeater {
            model: root.mode === "known" ? root.binds : []
            Row {
              required property var modelData
              required property int index
              anchors.verticalCenter: parent.verticalCenter
              spacing: root.gap
              Label {
                visible: parent.index > 0
                anchors.verticalCenter: parent.verticalCenter
                text: "·"
                opacity: 0.6
              }
              Keycaps { keys: parent.modelData.caps }
            }
          }
        }

        // Free combinations to pick from.
        Row {
          visible: root.mode === "ask"
          spacing: root.gap

          Label {
            anchors.verticalCenter: parent.verticalCenter
            opacity: 0.75
            text: root.suggestions.length > 0 ? strings.t("ask.pick") : strings.t("ask.none")
          }

          Repeater {
            model: root.mode === "ask" ? root.suggestions : []
            Button {
              required property var modelData
              anchors.verticalCenter: parent.verticalCenter
              bordered: true
              foreground: root.textColor
              // Built from this plugin's own key names: SUPER, SHIFT, a letter.
              text: modelData.caps.join(" + ")
              onClicked: root.choose(modelData)
            }
          }
        }

        Row {
          visible: root.mode === "ask"
          spacing: root.gap

          Button {
            foreground: Util.alpha(root.textColor, 0.75)
            fontSize: Style.font.bodySmall
            text: strings.t("ask.never")
            onClicked: root.neverAsk()
          }
          Button {
            foreground: Util.alpha(root.textColor, 0.75)
            fontSize: Style.font.bodySmall
            text: strings.t("ask.close")
            onClicked: root.close()
          }
        }
      }

      // Time left to choose, draining along the bottom edge.
      Rectangle {
        id: timeLeft
        property real fraction: 1
        visible: root.mode === "ask"
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.leftMargin: card.borderLeft
        anchors.bottomMargin: card.borderBottom
        width: (card.width - card.borderLeft - card.borderRight) * fraction
        height: Math.max(2, Style.space(2))
        color: Commons.Color.accent
        opacity: 0.8

        NumberAnimation {
          id: countdown
          target: timeLeft
          property: "fraction"
          from: 1
          to: 0
          // Constant motion, so linear; no bar at all when animations are off.
          duration: Style.duration(root.askMs)
        }
      }
    }
  }
}
