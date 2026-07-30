import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.clockDashboard
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.bar as Bar

Item {
    id: root
    property bool borderless: Config.options.bar.borderless
    implicitHeight: clockColumn.implicitHeight
    implicitWidth: Appearance.sizes.verticalBarWidth

    ColumnLayout {
        id: clockColumn
        anchors.centerIn: parent
        spacing: 0

        Repeater {
            model: DateTime.timeDisplay.split(/[: ]/)
            delegate: StyledText {
                required property string modelData
                Layout.alignment: Qt.AlignHCenter
                font.pixelSize: modelData.match(/am|pm/i) ? 
                    Appearance.font.pixelSize.smaller // Smaller "am"/"pm" text
                    : Appearance.font.pixelSize.large
                color: Appearance.inirEverywhere ? Appearance.inir.colText : Appearance.colors.colOnLayer1
                text: modelData.padStart(2, "0")
            }
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        // Left-click opens the clock dashboard; right-click the control panel
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: event => {
            if (event.button === Qt.LeftButton) {
                GlobalStates.clockDashboardOpen = !GlobalStates.clockDashboardOpen
            } else if (event.button === Qt.RightButton) {
                GlobalStates.controlPanelOpen = !GlobalStates.controlPanelOpen
            }
        }

    }

    // Slides out of this widget and stays next to it. Supersedes the old hover
    // tooltip, which showed a subset of the same information.
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
