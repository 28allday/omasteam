// omasteam-monitor — Omarchy-quattro-style system monitor panel, in pure QML.
//
// Opened from the bar's monitor chip; anchored top-right under it (same
// layer-shell recipe as the volume/network/bluetooth/power panels: Top|Right +
// margins, static size).
//
// Hero shows the CPU and its live load; below it meters for CPU / GPU / RAM /
// swap / disk, then the three hungriest processes.
//
// Read-only: no outbox, nothing to click. The launcher (omasteam-monitor)
// rewrites mon-state.json about once a second and this polls it — the whole
// panel is a view onto that one file.
import QtQuick
import QtQuick.Window
import org.kde.layershell as LayerShell

Window {
    id: win
    visible: true
    color: "transparent"
    width: 460
    height: 340

    LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorRight
    LayerShell.Window.margins.top: 8
    LayerShell.Window.margins.right: 12
    LayerShell.Window.layer: LayerShell.Window.LayerOverlay
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityExclusive

    // ---- theme palette (read from the bar daemon's state.json, like the bar) --
    property var st: ({})
    readonly property color cBg: st.colors ? st.colors.bg : "#1a1b26"
    readonly property color cFg: st.colors ? st.colors.fg : "#c0caf5"
    readonly property color cAccent: st.colors ? st.colors.accent : "#7aa2f7"
    readonly property color cDanger: "#f7768e"
    readonly property string fontFamily: "JetBrainsMono Nerd Font"
    readonly property string statePath: { var p = "@@STATE@@"; return p.charAt(0) === "/" ? p : "" }
    readonly property string monStatePath: { var p = "@@MONSTATE@@"; return p.charAt(0) === "/" ? p : "" }

    function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
    readonly property string icoCpu: String.fromCodePoint(0xF2DB)  // fa-microchip

    // Meters go amber past 75% and red past 90% — the same "is this the thing
    // that's hurting me" read the bar chip gives.
    function loadColor(pct) {
        if (pct >= 90) return cDanger
        if (pct >= 75) return "#e0af68"
        return cAccent
    }
    function gib(bytes) {
        if (!bytes || bytes <= 0) return "0"
        var g = bytes / 1073741824
        return (g >= 100 ? g.toFixed(0) : g.toFixed(1))
    }
    function pctOf(used, total) {
        if (!total || total <= 0) return 0
        return Math.max(0, Math.min(100, Math.round(100 * used / total)))
    }

    property string _lastPal: ""
    function pollPalette() {
        if (!statePath) return
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.responseText) {
                if (xhr.responseText === win._lastPal) return
                win._lastPal = xhr.responseText
                try { win.st = JSON.parse(xhr.responseText) } catch (e) {}
            }
        }
        xhr.open("GET", "file://" + statePath)
        xhr.send()
    }

    // ---- system stats (mon-state.json, rewritten ~1s by the launcher) --------
    property var mon: ({
        cpu: { pct: 0, temp: null, model: "", threads: 0, load: "" },
        gpu: { pct: null, temp: null },
        mem: { used: 0, total: 0 }, swap: { used: 0, total: 0 },
        disk: { used: 0, total: 0, mount: "/" },
        uptime: "", procs: []
    })
    property string _lastMon: ""
    function pollMon() {
        if (!monStatePath) return
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.responseText) {
                if (xhr.responseText === win._lastMon) return
                win._lastMon = xhr.responseText
                try {
                    var m = JSON.parse(xhr.responseText)
                    if (m && m.cpu) win.mon = m
                } catch (e) {}
            }
        }
        xhr.open("GET", "file://" + monStatePath)
        xhr.send()
    }
    // ONE onCompleted: a second handler on the same object is "Property value
    // set multiple times" — a silent no-window death.
    Component.onCompleted: { pollPalette(); pollMon() }
    Timer { interval: 1000; repeat: true; running: true; onTriggered: { win.pollMon(); win.pollPalette() } }

    function dismiss() { win.visible = false; quitTimer.start() }
    Timer { id: quitTimer; interval: 150; onTriggered: Qt.quit() }

    Rectangle {
        id: panel
        anchors.fill: parent
        radius: 14
        color: win.cBg
        border.color: win.alpha(win.cFg, 0.12)
        border.width: 1
        MouseArea { anchors.fill: parent }

        Item {
            id: keys
            focus: true
            Keys.onPressed: function(e) {
                if (e.key === Qt.Key_Escape) { win.dismiss(); e.accepted = true }
            }
        }

        Column {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            // ---- hero: cpu model · threads/load/uptime · live load % ---------
            Item {
                width: parent.width
                height: 44

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.right: heroPct.left
                    anchors.rightMargin: 10
                    spacing: 12

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: win.icoCpu
                        color: win.cAccent
                        font { family: win.fontFamily; pixelSize: 22 }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 22 - parent.spacing
                        spacing: 2
                        Text {
                            width: parent.width
                            text: win.mon.cpu.model ? win.mon.cpu.model : "System"
                            elide: Text.ElideRight
                            color: win.cFg
                            font { family: win.fontFamily; pixelSize: 14; bold: true }
                        }
                        Text {
                            width: parent.width
                            elide: Text.ElideRight
                            text: {
                                var parts = []
                                if (win.mon.cpu.threads) parts.push(win.mon.cpu.threads + " threads")
                                if (win.mon.cpu.load) parts.push("load " + win.mon.cpu.load)
                                if (win.mon.uptime) parts.push(win.mon.uptime)
                                return parts.join(" · ").toUpperCase()
                            }
                            color: win.alpha(win.cFg, 0.55)
                            font { family: win.fontFamily; pixelSize: 11; letterSpacing: 1.1 }
                        }
                    }
                }

                Text {
                    id: heroPct
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: (win.mon.cpu.pct || 0) + "%"
                    color: win.loadColor(win.mon.cpu.pct || 0)
                    font { family: win.fontFamily; pixelSize: 20; bold: true }
                }
            }

            // ---- meters -------------------------------------------------------
            Column {
                width: parent.width
                spacing: 6

                Meter {
                    label: "CPU"
                    pct: win.mon.cpu.pct || 0
                    detail: win.mon.cpu.temp === null || win.mon.cpu.temp === undefined
                        ? "" : win.mon.cpu.temp + "°C"
                }
                Meter {
                    label: "GPU"
                    // No amdgpu/i915 busy file (VMs, some iGPUs): show the meter
                    // empty with an em dash rather than a confident 0%.
                    known: win.mon.gpu.pct !== null && win.mon.gpu.pct !== undefined
                    pct: known ? win.mon.gpu.pct : 0
                    detail: win.mon.gpu.temp === null || win.mon.gpu.temp === undefined
                        ? "" : win.mon.gpu.temp + "°C"
                }
                Meter {
                    label: "RAM"
                    pct: win.pctOf(win.mon.mem.used, win.mon.mem.total)
                    detail: win.gib(win.mon.mem.used) + " / " + win.gib(win.mon.mem.total) + " GiB"
                }
                Meter {
                    label: "SWAP"
                    known: win.mon.swap.total > 0
                    pct: win.pctOf(win.mon.swap.used, win.mon.swap.total)
                    detail: win.mon.swap.total > 0
                        ? win.gib(win.mon.swap.used) + " / " + win.gib(win.mon.swap.total) + " GiB"
                        : "none"
                }
                Meter {
                    label: "DISK"
                    pct: win.pctOf(win.mon.disk.used, win.mon.disk.total)
                    detail: win.gib(win.mon.disk.used) + " / " + win.gib(win.mon.disk.total)
                        + " GiB " + (win.mon.disk.mount || "")
                }
            }

            // ---- top processes -------------------------------------------------
            Column {
                width: parent.width
                spacing: 4

                Text {
                    text: "TOP PROCESSES"
                    color: win.alpha(win.cFg, 0.45)
                    font { family: win.fontFamily; pixelSize: 10; bold: true; letterSpacing: 1.4 }
                }

                Repeater {
                    model: win.mon.procs

                    Item {
                        required property var modelData
                        width: parent.width
                        height: 24

                        Text {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 160
                            elide: Text.ElideRight
                            text: modelData.name
                            color: win.cFg
                            font { family: win.fontFamily; pixelSize: 12 }
                        }
                        Text {
                            anchors.right: memText.left
                            anchors.rightMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.cpu.toFixed(1) + "% cpu"
                            color: win.alpha(win.cFg, 0.6)
                            font { family: win.fontFamily; pixelSize: 11 }
                        }
                        Text {
                            id: memText
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: 64
                            horizontalAlignment: Text.AlignRight
                            text: modelData.mem.toFixed(1) + "% mem"
                            color: win.alpha(win.cFg, 0.6)
                            font { family: win.fontFamily; pixelSize: 11 }
                        }
                    }
                }
            }
        }
    }

    // ---- one labelled meter: NAME … detail, with a fill bar under it ---------
    component Meter: Item {
        property string label: ""
        property string detail: ""
        property int pct: 0
        property bool known: true

        width: parent.width
        height: 28

        Text {
            id: meterLabel
            anchors.left: parent.left
            anchors.top: parent.top
            text: label
            color: win.alpha(win.cFg, 0.75)
            font { family: win.fontFamily; pixelSize: 11; bold: true; letterSpacing: 1.2 }
        }
        Text {
            anchors.right: parent.right
            anchors.top: parent.top
            text: (known ? pct + "%" : "—") + (detail ? "  ·  " + detail : "")
            color: win.alpha(win.cFg, 0.6)
            font { family: win.fontFamily; pixelSize: 11 }
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 6
            radius: 3
            color: win.alpha(win.cFg, 0.12)

            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                radius: parent.radius
                width: known ? Math.max(parent.height, parent.width * pct / 100) : 0
                color: win.loadColor(pct)
                Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                Behavior on color { ColorAnimation { duration: 220 } }
            }
        }
    }
}
