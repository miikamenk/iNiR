import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root
    property bool _presentedOpen: false
    Component.onCompleted: {
        if (GlobalStates.wallpaperSelectorOpen)
            Qt.callLater(() => { root._presentedOpen = GlobalStates.wallpaperSelectorOpen })
    }

    Loader {
        id: wallpaperSelectorLoader
        active: GlobalStates.wallpaperSelectorOpen || _wsClosing

        property bool _wsClosing: false

        Connections {
            target: GlobalStates
            function onWallpaperSelectorOpenChanged() {
                if (GlobalStates.wallpaperSelectorOpen) {
                    Qt.callLater(() => { root._presentedOpen = GlobalStates.wallpaperSelectorOpen })
                } else {
                    root._presentedOpen = false
                    wallpaperSelectorLoader._wsClosing = true
                    _wsCloseTimer.restart()
                }
            }
        }

        Timer {
            id: _wsCloseTimer
            interval: 200
            onTriggered: wallpaperSelectorLoader._wsClosing = false
        }

        sourceComponent: PanelWindow {
            id: panelWindow
            // Show on the target monitor so focus stays correct after close
            screen: {
                const targetMon = GlobalStates.wallpaperSelectorTargetMonitor
                if (targetMon) {
                    const s = Quickshell.screens.find(s => s.name === targetMon)
                    if (s) return s
                }
                return GlobalStates.primaryScreen
            }
            readonly property HyprlandMonitor monitor: CompositorService.isHyprland ? Hyprland.monitorFor(panelWindow.screen) : null
            property bool monitorIsFocused: CompositorService.isHyprland 
                ? (Hyprland.focusedMonitor?.id == monitor?.id)
                : (CompositorService.isNiri ? (panelWindow.screen?.name === NiriService.currentOutput) : true)

            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:wallpaperSelector"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: GlobalStates.wallpaperSelectorOpen && !GlobalStates.regionSelectorOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            color: "transparent"

            anchors {
                top: true
                left: true
                right: true
                bottom: true
            }

            CompositorFocusGrab { // Click outside to close (Hyprland)
                id: grab
                windows: [ panelWindow ]
                active: CompositorService.isHyprland && wallpaperSelectorLoader.active
                onCleared: () => {
                    if (!active) GlobalStates.wallpaperSelectorOpen = false;
                }
            }

            // Click outside to close (all compositors)
            MouseArea {
                anchors.fill: parent
                onClicked: mouse => {
                    const localPos = mapToItem(content, mouse.x, mouse.y)
                    if (localPos.x < 0 || localPos.x > content.width
                            || localPos.y < 0 || localPos.y > content.height) {
                        GlobalStates.wallpaperSelectorOpen = false;
                    }
                }
            }

            WallpaperSelectorContent {
                id: content
                anchors {
                    top: parent.top
                    horizontalCenter: parent.horizontalCenter
                    topMargin: (Config.options?.bar?.vertical ?? false) ? Appearance.sizes.hyprlandGapsOut : Appearance.sizes.barHeight + Appearance.sizes.hyprlandGapsOut
                }
                // Clamp to the screen so the wide layout degrades to a narrower
                // panel on small displays instead of overflowing off-screen.
                readonly property real _gaps: Appearance.sizes.hyprlandGapsOut * 2
                implicitHeight: Math.min(Appearance.sizes.wallpaperSelectorHeight, panelWindow.height - content.anchors.topMargin - content._gaps)
                implicitWidth: Math.min(Appearance.sizes.wallpaperSelectorWidth, panelWindow.width - content._gaps)

                // Scale + fade + a short drop, with an asymmetric curve pair: the
                // entrance decelerates in, the exit accelerates away and is quicker.
                transformOrigin: Item.Top
                scale: root._presentedOpen ? 1.0 : 0.93
                opacity: root._presentedOpen ? 1.0 : 0.0
                transform: Translate {
                    y: root._presentedOpen ? 0 : -22
                    Behavior on y {
                        enabled: Appearance.animationsEnabled
                        NumberAnimation {
                            duration: root._presentedOpen ? Appearance.animation.overshootEnter.duration : Appearance.animation.menuExit.duration
                            easing.type: root._presentedOpen ? Appearance.animation.overshootEnter.type : Appearance.animation.menuExit.type
                            easing.overshoot: Appearance.animation.overshootEnter.overshoot
                        }
                    }
                }
                Behavior on scale {
                    enabled: Appearance.animationsEnabled
                    NumberAnimation {
                        duration: root._presentedOpen ? Appearance.animation.menuEnter.duration : Appearance.animation.menuExit.duration
                        easing.type: root._presentedOpen ? Appearance.animation.menuEnter.type : Appearance.animation.menuExit.type
                    }
                }
                Behavior on opacity {
                    enabled: Appearance.animationsEnabled
                    NumberAnimation {
                        duration: root._presentedOpen ? Appearance.animation.menuEnter.duration : Appearance.animation.menuExit.duration
                        easing.type: root._presentedOpen ? Appearance.animation.menuEnter.type : Appearance.animation.menuExit.type
                    }
                }
            }
        }
    }

}
