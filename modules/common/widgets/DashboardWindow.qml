pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell
import Quickshell.Wayland

// Shared fullscreen window for centered dashboard panels (clock/system dashboards).
// Encapsulates: overlay PanelWindow, backdrop-click close, pop open/close
// animation, Escape handling, focus grab. Same proven pattern as ControlPanel.
//
// Usage:
//   DashboardWindow {
//       open: GlobalStates.clockDashboardOpen
//       panelNamespace: "quickshell:clockDashboard"
//       panelWidth: 920
//       onHideRequested: GlobalStates.clockDashboardOpen = false
//       contentComponent: ClockDashboardContent {}
//   }
PanelWindow {
    id: root

    // Public API
    property bool open: false
    property string panelNamespace: "quickshell:dashboard"
    property alias contentComponent: contentLoader.sourceComponent
    property real panelWidth: 900
    property bool keepLoaded: false
    property real maxPanelHeightRatio: 0.86
    signal hideRequested()

    readonly property real screenWidth: screen?.width ?? 1920
    readonly property real screenHeight: screen?.height ?? 1080
    readonly property real maxPanelHeight: Math.round(screenHeight * maxPanelHeightRatio)

    visible: false
    onOpenChanged: {
        if (root.open) {
            _closeTimer.stop()
            root.visible = true
        } else {
            _closeTimer.restart()
        }
    }

    Timer {
        id: _closeTimer
        interval: 220
        onTriggered: root.visible = false
    }

    exclusiveZone: 0
    implicitWidth: screen?.width ?? 1920
    implicitHeight: screen?.height ?? 1080
    WlrLayershell.namespace: root.panelNamespace
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    color: "transparent"

    anchors {
        top: true
        right: true
        bottom: true
        left: true
    }

    CompositorFocusGrab {
        id: grab
        windows: [root]
        active: CompositorService.isHyprland && root.visible
        onCleared: () => {
            if (!active) root.hideRequested()
        }
    }

    // Backdrop click to close
    MouseArea {
        anchors.fill: parent
        onClicked: mouse => {
            const localPos = mapToItem(contentLoader, mouse.x, mouse.y)
            if (localPos.x < 0 || localPos.x > contentLoader.width
                    || localPos.y < 0 || localPos.y > contentLoader.height) {
                root.hideRequested()
            }
        }
    }

    Loader {
        id: contentLoader
        active: root.open || root.keepLoaded
        anchors.centerIn: parent

        width: Math.min(root.panelWidth, root.screenWidth - 48)
        height: item?.implicitHeight ? Math.min(item.implicitHeight, root.maxPanelHeight) : root.maxPanelHeight

        // Shell desaturation effect
        layer.enabled: Appearance.shouldDesaturate("overlays") && contentLoader.visible
        layer.effect: ShellDesaturationEffect {}

        property real panelTranslateY: -24
        opacity: 0
        scale: 0.94
        transform: Translate {
            y: contentLoader.panelTranslateY
        }

        states: [
            State {
                name: "open"
                when: root.open
                PropertyChanges {
                    target: contentLoader
                    opacity: 1
                    scale: 1
                    panelTranslateY: 0
                }
            },
            State {
                name: "closed"
                when: !root.open
                PropertyChanges {
                    target: contentLoader
                    opacity: 0
                    scale: 0.94
                    panelTranslateY: -24
                }
            }
        ]
        transitions: [
            Transition {
                to: "open"
                enabled: Appearance.animationsEnabled
                ParallelAnimation {
                    NumberAnimation {
                        target: contentLoader
                        property: "opacity"
                        from: 0
                        to: 1
                        duration: Math.round((Appearance.animation?.elementMoveEnter?.duration ?? 400) * 0.7)
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves?.standardDecel ?? [0, 0, 0, 1, 1, 1]
                    }
                    SequentialAnimation {
                        NumberAnimation {
                            target: contentLoader
                            property: "scale"
                            from: 0.94
                            to: 1.018
                            duration: Math.round((Appearance.animation?.elementMoveEnter?.duration ?? 400) * 0.62)
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Appearance.animationCurves?.emphasizedDecel ?? [0.05, 0.7, 0.1, 1, 1, 1]
                        }
                        NumberAnimation {
                            target: contentLoader
                            property: "scale"
                            to: 1
                            duration: Math.round((Appearance.animation?.elementMoveEnter?.duration ?? 400) * 0.38)
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Appearance.animationCurves?.expressiveEffects ?? [0.2, 0, 0, 1, 1, 1]
                        }
                    }
                    SequentialAnimation {
                        NumberAnimation {
                            target: contentLoader
                            property: "panelTranslateY"
                            from: -24
                            to: 6
                            duration: Math.round((Appearance.animation?.elementMoveEnter?.duration ?? 400) * 0.62)
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Appearance.animationCurves?.emphasizedDecel ?? [0.05, 0.7, 0.1, 1, 1, 1]
                        }
                        NumberAnimation {
                            target: contentLoader
                            property: "panelTranslateY"
                            to: 0
                            duration: Math.round((Appearance.animation?.elementMoveEnter?.duration ?? 400) * 0.38)
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Appearance.animationCurves?.expressiveEffects ?? [0.2, 0, 0, 1, 1, 1]
                        }
                    }
                }
            },
            Transition {
                to: "closed"
                enabled: Appearance.animationsEnabled
                ParallelAnimation {
                    NumberAnimation {
                        target: contentLoader
                        property: "opacity"
                        to: 0
                        duration: Math.round((Appearance.animation?.elementMoveExit?.duration ?? 200) * 0.7)
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves?.standardAccel ?? [0.3, 0, 1, 1, 1, 1]
                    }
                    NumberAnimation {
                        target: contentLoader
                        property: "scale"
                        to: 0.94
                        duration: Appearance.animation?.elementMoveExit?.duration ?? 200
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves?.emphasizedAccel ?? [0.3, 0, 0.8, 0.15, 1, 1]
                    }
                    NumberAnimation {
                        target: contentLoader
                        property: "panelTranslateY"
                        to: -24
                        duration: Appearance.animation?.elementMoveExit?.duration ?? 200
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves?.emphasizedAccel ?? [0.3, 0, 0.8, 0.15, 1, 1]
                    }
                }
            }
        ]

        focus: root.open
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) {
                root.hideRequested()
                event.accepted = true
            }
        }
    }
}
