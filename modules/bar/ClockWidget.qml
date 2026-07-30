import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.clockDashboard
import qs.services
import Quickshell
import QtQuick
import QtQuick.Layouts
import Quickshell

Item {
    id: root
    property bool borderless: Config.options?.bar?.borderless ?? false
    property bool showDate: Config.options?.bar?.verbose ?? true
    implicitWidth: rowLayout.implicitWidth
    implicitHeight: Appearance.sizes.barHeight

    // Easter egg: long-press the clock → bedtime lecture, whatever the hour
    TapHandler {
        enabled: Config.options?.mascot?.enable ?? false
        onLongPressed: Quickshell.execDetached([Quickshell.shellPath("scripts/inir"), "mascot", "appear", "late-night", "top"])
    }

    RowLayout {
        id: rowLayout
        anchors.centerIn: parent
        spacing: 4

        StyledText {
            font.pixelSize: Appearance.font.pixelSize.large
            color: Appearance.angelEverywhere ? Appearance.angel.colText
                : Appearance.inirEverywhere ? Appearance.inir.colText : Appearance.colors.colOnLayer1
            text: DateTime.timeDisplay
        }

        Revealer {
            reveal: root.showDate
            StyledText {
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.angelEverywhere ? Appearance.angel.colTextSecondary
                    : Appearance.inirEverywhere ? Appearance.inir.colText : Appearance.colors.colOnLayer1
                text: "•"
            }
        }

        Revealer {
            reveal: root.showDate
            StyledText {
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.angelEverywhere ? Appearance.angel.colText
                    : Appearance.inirEverywhere ? Appearance.inir.colText : Appearance.colors.colOnLayer1
                text: DateTime.date
            }
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        // Hovering reveals the clock dashboard; left-click pins it open.
        // Right-click still opens the control panel.
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: event => {
            if (event.button === Qt.LeftButton) {
                GlobalStates.clockDashboardOpen = !GlobalStates.clockDashboardOpen
            } else if (event.button === Qt.RightButton) {
                GlobalStates.controlPanelOpen = !GlobalStates.controlPanelOpen
            }
        }
    }

    // Slides out of this widget and stays next to it. The dashboard supersedes
    // the old hover tooltip, which showed a subset of the same information.
    BarAnchoredPanel {
        anchorItem: root
        anchorWindow: root.QsWindow.window
        pinned: GlobalStates.clockDashboardOpen
        anchorHovered: mouseArea.containsMouse
        popupNamespace: "quickshell:clockDashboard"
        onCloseRequested: GlobalStates.clockDashboardOpen = false
        contentComponent: ClockDashboardContent {}
    }
}
