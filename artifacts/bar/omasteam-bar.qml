// omasteam-bar — a quattro-style top bar for SteamOS + KDE, in pure QML.
//
// Runs as a Wayland layer-shell surface (via org.kde.layershell, already on
// SteamOS) launched by `omasteam-bar`. It has no backend of its own: the
// companion `omasteam-bar-daemon` polls the system + active omasteam theme and
// writes state.json, which this bar reads on a Timer. Clicks are pushed back
// to the daemon through a tiny SQLite outbox (LocalStorage) it drains.
//
// Layout mirrors Omarchy 4's bar: menu + workspaces (left), clock (center),
// network / volume / battery / power (right).
import QtQuick
import QtQuick.Window
import QtQuick.LocalStorage
import org.kde.layershell as LayerShell

Window {
    id: win
    visible: true
    color: "transparent"
    height: 34

    LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorLeft | LayerShell.Window.AnchorRight
    LayerShell.Window.layer: LayerShell.Window.LayerTop
    LayerShell.Window.exclusionZone: 34
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityNone

    // ---- state -----------------------------------------------------------
    property var st: ({})
    readonly property color cBg: st.colors ? st.colors.bg : "#1a1b26"
    readonly property color cFg: st.colors ? st.colors.fg : "#c0caf5"
    readonly property color cAccent: st.colors ? st.colors.accent : "#7aa2f7"
    readonly property string fontFamily: "JetBrainsMono Nerd Font"
    // The launcher renders @@STATE@@ to the absolute state.json path. Plain QML
    // can read neither argv nor env reliably under qmlscene, so templating is
    // the robust way in. An un-rendered placeholder disables polling.
    readonly property string statePath: { var p = "@@STATE@@"; return p.charAt(0) === "/" ? p : "" }

    function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

    // Nerd Font (FontAwesome) glyphs.
    readonly property string icoMenu:    ""
    readonly property string icoWifi:    ""
    readonly property string icoEth:   String.fromCodePoint(0xF0200)  // md-ethernet
    readonly property string icoCpu:   String.fromCodePoint(0xF2DB)   // fa-microchip — system monitor
    readonly property string icoBt:     String.fromCodePoint(0xF00AF)  // md-bluetooth
    readonly property string icoBtConn: String.fromCodePoint(0xF00B1)  // md-bluetooth-connect
    readonly property string icoBtOff:  String.fromCodePoint(0xF00B2)  // md-bluetooth-off
    readonly property string icoNoNet:   ""
    readonly property string icoVol:     ""
    readonly property string icoVolLow:  ""
    readonly property string icoMute:    ""
    readonly property string icoBolt:    ""
    readonly property string icoPower:   ""

    // fa-moon-o, from the legacy FA4 block this Nerd Font patch actually
    // carries. Verified with the fc-list charset check in NOTES.md §6 — the FA5
    // moon is absent here and would render as an empty box, same trap as the
    // menu's old Appearance glyph.
    readonly property string icoNight: String.fromCodePoint(0xF186)
    // fa-desktop. Deliberately not the microchip above — that one is already the
    // system monitor, and two screen-ish glyphs side by side read as one control.
    readonly property string icoDisplay: String.fromCodePoint(0xF108)

    function batIcon(pct) {
        if (pct >= 88) return ""
        if (pct >= 63) return ""
        if (pct >= 38) return ""
        if (pct >= 13) return ""
        return ""
    }

    readonly property string icoGaming: ""   // Steam glyph — Return to Gaming Mode

    // ---- state polling ---------------------------------------------------
    // Same no-op guard as the menu: only reassign win.st when state.json
    // actually changed. Reassigning identical state every 400ms re-dirties
    // every binding in the bar for nothing — the surface is opaque so it can't
    // accumulate like the menu scrim, but the repaints are pure waste.
    property string _lastRaw: ""
    function poll() {
        if (!statePath) return
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.responseText) {
                if (xhr.responseText === win._lastRaw) return
                win._lastRaw = xhr.responseText
                try { win.st = JSON.parse(xhr.responseText) } catch (e) {}
            }
        }
        // No query string: a "?_=" cache-buster makes a file:// path invalid.
        // XHR re-reads the file each call anyway (no HTTP caching for file://).
        xhr.open("GET", "file://" + statePath)
        xhr.send()
    }
    Timer { interval: 400; running: true; repeat: true; triggeredOnStart: true; onTriggered: win.poll() }

    // ---- click outbox (SQLite drained by the daemon) ---------------------
    function db() {
        return LocalStorage.openDatabaseSync("omasteam_bar", "1.0", "omasteam bar outbox", 100000)
    }
    function sendCmd(cmd) {
        try {
            db().transaction(function(tx) {
                tx.executeSql("CREATE TABLE IF NOT EXISTS outbox(id INTEGER PRIMARY KEY AUTOINCREMENT, cmd TEXT)")
                tx.executeSql("INSERT INTO outbox(cmd) VALUES(?)", [cmd])
            })
        } catch (e) { console.log("sendCmd failed:", e) }
    }

    // ---- bar surface -----------------------------------------------------
    Rectangle {
        anchors.fill: parent
        color: win.cBg

        // subtle bottom hairline
        Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: 1; color: win.alpha(win.cFg, 0.08) }

        // ---------- LEFT: menu + workspaces ----------
        Row {
            id: left
            anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
            spacing: 6

            // system menu — Meta+Alt+Space. One menu for everything: settings,
            // omasteam's panels, and the Applications level (which is why there
            // is no separate app-launcher chip next to this one anymore).
            Chip {
                glyph: win.icoMenu
                glyphColor: win.cAccent
                onClicked: win.sendCmd("menu")
            }

            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                Repeater {
                    model: win.st.desktops ? win.st.desktops.count : 0
                    delegate: Rectangle {
                        required property int index
                        readonly property int ws: index + 1
                        readonly property bool active: win.st.desktops && win.st.desktops.current === ws
                        width: 22; height: 22; radius: 6
                        color: active ? win.cAccent
                                      : (wsHover.hovered ? win.alpha(win.cFg, 0.10) : win.alpha(win.cFg, 0.04))
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Text {
                            anchors.centerIn: parent; text: parent.ws
                            color: parent.active ? win.cBg : win.alpha(win.cFg, 0.85)
                            font { family: win.fontFamily; pixelSize: 12; bold: parent.active }
                        }
                        HoverHandler { id: wsHover }
                        TapHandler { onTapped: win.sendCmd("desktop-" + parent.ws) }
                    }
                }
            }
        }

        // ---------- CENTER: clock ----------
        Row {
            anchors.centerIn: parent
            spacing: 8
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: (win.st.day || "") + "  " + (win.st.time || "--:--")
                color: win.cFg
                font { family: win.fontFamily; pixelSize: 13; bold: true }
            }
        }

        // ---------- RIGHT: net / volume / battery / power ----------
        Row {
            id: right
            anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
            spacing: 4

            // Return to Gaming Mode — the Deck essential. Kept in the bar so it
            // survives even if the Plasma panel is hidden.
            Chip {
                glyph: win.icoGaming
                glyphColor: win.cAccent
                hoverGlyphColor: win.cFg
                onClicked: win.sendCmd("return-to-gaming")
            }

            // separator
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 1; height: 14; color: win.alpha(win.cFg, 0.15)
            }

            // system monitor (cpu load)
            Chip {
                readonly property var sys: win.st.sys || ({ cpu: 0, mem: 0 })
                glyph: win.icoCpu
                label: sys.cpu + "%"
                glyphColor: sys.cpu >= 85 ? "#f7768e" : win.cFg
                onClicked: win.sendCmd("mon-panel")
            }

            // display configuration — resolution / scale / rotation. Tap toggles
            // the panel; it single-instances, so a second tap closes it. No
            // long-press action: every geometry change in there is applied on
            // approval with a revert timer, which is not something to put behind
            // an accidental hold on a handheld.
            Chip {
                glyph: win.icoDisplay
                glyphColor: win.cFg
                onClicked: win.sendCmd("disp-panel")
            }

            // night light — tap toggles the panel (it single-instances, so a
            // second tap closes it); long-press flips the tint straight on/off
            // without opening anything, mirroring the volume chip's tap/hold
            // split. Hidden entirely when KWin reports it cannot tint, so the
            // chip never sits there as a dead control.
            Chip {
                readonly property var nl: win.st.nl || ({ avail: false, on: false })
                visible: nl.avail
                glyph: win.icoNight
                glyphColor: nl.on ? "#e0af68" : win.alpha(win.cFg, 0.45)
                hoverGlyphColor: win.cFg
                onClicked: win.sendCmd("nl-panel")
                onLongPressed: win.sendCmd("nl-toggle")
            }

            // bluetooth
            Chip {
                readonly property var bt: win.st.bt || ({ on: false, name: "" })
                glyph: bt.name ? win.icoBtConn : (bt.on ? win.icoBt : win.icoBtOff)
                label: bt.name || ""
                glyphColor: bt.on ? win.cFg : win.alpha(win.cFg, 0.45)
                onClicked: win.sendCmd("bt-panel")
            }

            // network
            Chip {
                readonly property var net: win.st.net || ({ type: "none", name: "" })
                glyph: net.type === "wifi" ? win.icoWifi : (net.type === "ethernet" ? win.icoEth : win.icoNoNet)
                label: net.type === "wifi" ? net.name : ""
                onClicked: win.sendCmd("net-panel")
            }

            // volume
            Chip {
                readonly property int vol: win.st.vol === undefined ? -1 : win.st.vol
                readonly property bool muted: win.st.muted === true
                glyph: muted ? win.icoMute : (vol < 34 ? win.icoVolLow : win.icoVol)
                label: vol < 0 ? "" : (vol + "%")
                glyphColor: muted ? win.alpha(win.cFg, 0.5) : win.cFg
                onClicked: win.sendCmd("vol-panel")
                onLongPressed: win.sendCmd("vol-mute")
                onWheelUp: win.sendCmd("vol-up")
                onWheelDown: win.sendCmd("vol-down")
            }

            // battery (only if the daemon reported one)
            Chip {
                visible: win.st.battery !== undefined && win.st.battery !== null
                readonly property var bat: win.st.battery || ({ pct: 0, charging: false })
                glyph: bat.charging ? win.icoBolt : win.batIcon(bat.pct)
                label: bat.pct + "%"
                glyphColor: (!bat.charging && bat.pct <= 15) ? "#f7768e" : win.cFg
                // Every other chip opens something; send this one to the power
                // panel, which is where battery state belongs anyway.
                onClicked: win.sendCmd("power")
            }

            // power
            Chip {
                glyph: win.icoPower
                glyphColor: win.cFg
                hoverGlyphColor: "#f7768e"
                onClicked: win.sendCmd("power")
            }
        }
    }

    // ---- reusable chip ---------------------------------------------------
    component Chip: Rectangle {
        id: chip
        property string glyph: ""
        property string label: ""
        property int maxLabelWidth: 140
        property color glyphColor: win.cFg
        property color hoverGlyphColor: glyphColor
        signal clicked()
        signal longPressed()
        signal wheelUp()
        signal wheelDown()

        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        height: 24
        width: content.implicitWidth + 16
        radius: 6
        color: hh.hovered ? win.alpha(win.cFg, 0.10) : "transparent"
        Behavior on color { ColorAnimation { duration: 120 } }

        Row {
            id: content
            anchors.centerIn: parent
            spacing: 6
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: chip.glyph
                visible: chip.glyph !== ""
                color: hh.hovered ? chip.hoverGlyphColor : chip.glyphColor
                font { family: win.fontFamily; pixelSize: 14 }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: chip.label
                visible: chip.label !== ""
                // Labels are user/AP-controlled (SSIDs, Bluetooth device names)
                // and can be long enough to push this whole cluster across the
                // clock — on a Deck's 1280px panel, into the workspaces too.
                // Clamp and ellipsize instead of growing the bar.
                width: Math.min(implicitWidth, chip.maxLabelWidth)
                elide: Text.ElideRight
                color: win.cFg
                font { family: win.fontFamily; pixelSize: 12 }
            }
        }

        HoverHandler { id: hh; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: chip.clicked(); onLongPressed: chip.longPressed() }
        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: function(e) { if (e.angleDelta.y > 0) chip.wheelUp(); else if (e.angleDelta.y < 0) chip.wheelDown() }
        }
    }
}
