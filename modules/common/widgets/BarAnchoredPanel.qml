pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Wayland

// Bar-anchored slide-out panel for the ii bar (the ii-side counterpart to
// waffle's BarPopup). Used by the clock and system dashboards so they emerge
// from their own bar widget and stay next to it instead of floating centered.
//
// Behaviour it encapsulates:
//   - Anchors a PopupWindow to `anchorItem`, on the side away from the bar.
//   - Slides the content out from behind the bar edge. The popup surface has a
//     fixed size, so content translated past the edge is simply not rendered —
//     that natural clip is what makes it look like it comes out of the widget.
//   - Shows on hover (`anchorHovered`), stays on click (`pinned`), and closes
//     again once the pointer leaves both the widget and the panel.
//   - Click-outside (Niri needs an explicit backdrop) and Escape both emit
//     closeRequested; only while pinned, so hover mode never grabs input.
//
// Content is created once on first reveal and then kept, so hovering repeatedly
// does not rebuild heavy children (calendar, weather, graphs).
Loader {
    id: root

    // ── Inputs ──
    required property Item anchorItem
    property var anchorWindow: null
    property Component contentComponent: null
    // Click-to-pin state. Owned by the caller (a GlobalStates flag) so IPC and
    // keybinds can drive the same panel.
    property bool pinned: false
    // Set by the bar widget's hover area.
    property bool anchorHovered: false
    property real edgeMargin: 6
    // Dwell time before hover reveals the panel, so sweeping the pointer along
    // the bar doesn't fling a full dashboard open.
    property int hoverOpenDelay: 350
    property int hoverCloseDelay: 300
    property string popupNamespace: "quickshell:barAnchoredPanel"

    // Bar placement. For the vertical bar `bar.bottom` means "right-hand side".
    readonly property bool barVertical: Config.options?.bar?.vertical ?? false
    readonly property bool barFarSide: Config.options?.bar?.bottom ?? false

    signal closeRequested

    // ── Reveal state ──
    property bool _panelHovered: false
    property bool _hoverArmed: false
    // Blocks hover re-opening after an explicit click-to-close, until the
    // pointer actually leaves the widget.
    property bool _hoverSuppressed: false
    readonly property bool shouldShow: root.pinned || root._hoverArmed || root._panelHovered

    onPinnedChanged: {
        if (!root.pinned) {
            root._hoverArmed = false;
            root._hoverSuppressed = root.anchorHovered;
        }
    }
    onAnchorHoveredChanged: if (!root.anchorHovered)
        root._hoverSuppressed = false

    Timer {
        interval: root.hoverOpenDelay
        running: root.anchorHovered && !root.pinned && !root._hoverArmed && !root._hoverSuppressed
        onTriggered: root._hoverArmed = true
    }
    // Hover-revealed panels retract once the pointer leaves both surfaces.
    // Pinned ones stay until dismissed.
    Timer {
        interval: root.hoverCloseDelay
        running: root._hoverArmed && !root.anchorHovered && !root._panelHovered
        onTriggered: root._hoverArmed = false
    }

    // Keep the content alive after the first reveal.
    property bool _everShown: false
    onShouldShowChanged: if (root.shouldShow)
        root._everShown = true
    active: root._everShown

    sourceComponent: PopupWindow {
        id: popup

        // Stays mapped while closing so the slide-out can play.
        visible: root.shouldShow || closeAnim.running
        color: "transparent"

        anchor {
            window: root.anchorWindow
            item: root.anchorItem
            adjustment: PopupAdjustment.SlideX | PopupAdjustment.SlideY
            edges: root.barVertical ? (root.barFarSide ? Edges.Left : Edges.Right) : (root.barFarSide ? Edges.Top : Edges.Bottom)
            gravity: root.barVertical ? (root.barFarSide ? Edges.Left : Edges.Right) : (root.barFarSide ? Edges.Top : Edges.Bottom)
        }

        // Clamped to the screen so a tall dashboard can't grow past the display
        // (the old centered window capped this at a ratio of screen height).
        readonly property real availWidth: (root.anchorWindow?.screen?.width ?? 1920) - 24
        readonly property real availHeight: (root.anchorWindow?.screen?.height ?? 1080) - Appearance.sizes.barHeight - 24
        implicitWidth: Math.min((contentLoader.implicitWidth > 0 ? contentLoader.implicitWidth : 400) + root.edgeMargin * 2, availWidth)
        implicitHeight: Math.min((contentLoader.implicitHeight > 0 ? contentLoader.implicitHeight : 300) + root.edgeMargin * 2, availHeight)

        // Distance the content travels, along the axis pointing away from the bar.
        readonly property real slideDistance: root.barVertical ? popup.implicitWidth : popup.implicitHeight
        // 0 = tucked behind the bar, 1 = fully out.
        property real slideProgress: 0

        // The first reveal happens as this component is created, so shouldShow
        // already changed before Connections existed.
        Component.onCompleted: if (root.shouldShow)
            openAnim.restart()

        Connections {
            target: root
            function onShouldShowChanged(): void {
                if (root.shouldShow) {
                    closeAnim.stop();
                    openAnim.restart();
                } else {
                    openAnim.stop();
                    closeAnim.restart();
                }
            }
        }

        ParallelAnimation {
            id: openAnim
            NumberAnimation {
                target: popup
                property: "slideProgress"
                to: 1
                duration: Appearance.animationsEnabled ? (Appearance.animation?.elementMoveEnter?.duration ?? 300) : 0
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves?.emphasizedDecel ?? [0.05, 0.7, 0.1, 1, 1, 1]
            }
            NumberAnimation {
                target: contentLoader
                property: "opacity"
                to: 1
                duration: Appearance.animationsEnabled ? Math.round((Appearance.animation?.elementMoveEnter?.duration ?? 300) * 0.6) : 0
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves?.standardDecel ?? [0, 0, 0, 1, 1, 1]
            }
        }

        ParallelAnimation {
            id: closeAnim
            NumberAnimation {
                target: popup
                property: "slideProgress"
                to: 0
                duration: Appearance.animationsEnabled ? (Appearance.animation?.elementMoveExit?.duration ?? 200) : 0
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves?.emphasizedAccel ?? [0.3, 0, 0.8, 0.15, 1, 1]
            }
            NumberAnimation {
                target: contentLoader
                property: "opacity"
                to: 0
                duration: Appearance.animationsEnabled ? Math.round((Appearance.animation?.elementMoveExit?.duration ?? 200) * 0.8) : 0
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves?.standardAccel ?? [0.3, 0, 1, 1, 1, 1]
            }
        }

        Shortcut {
            sequences: [StandardKey.Cancel]
            enabled: root.pinned
            onActivated: root.closeRequested()
        }

        Loader {
            id: contentLoader
            sourceComponent: root.contentComponent
            opacity: 0

            // Tucked behind the bar at progress 0, in place at 1. The bar sits on
            // the popup's near edge, so the content hides toward that edge:
            // negative for a top/left bar, positive for a bottom/right one.
            readonly property real signedOffset: (1 - popup.slideProgress) * popup.slideDistance * (root.barFarSide ? 1 : -1)
            x: root.edgeMargin + (root.barVertical ? signedOffset : 0)
            y: root.edgeMargin + (root.barVertical ? 0 : signedOffset)

            HoverHandler {
                id: panelHover
            }
            Binding {
                target: root
                property: "_panelHovered"
                value: panelHover.hovered
            }
        }

        // Niri has no focus-grab, so an explicit full-screen backdrop catches
        // clicks outside. Only while pinned — otherwise it would sit over the
        // bar and swallow the hover that keeps the panel open.
        Loader {
            active: root.pinned && CompositorService.isNiri
            sourceComponent: PanelWindow {
                anchors {
                    top: true
                    bottom: true
                    left: true
                    right: true
                }
                color: "transparent"
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.layer: WlrLayer.Top
                WlrLayershell.namespace: root.popupNamespace + "Backdrop"

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.closeRequested()
                }
            }
        }

        CompositorFocusGrab {
            active: root.pinned && CompositorService.isHyprland && popup.visible
            windows: [popup]
            onCleared: root.closeRequested()
        }
    }
}
