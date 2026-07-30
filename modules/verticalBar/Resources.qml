import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.systemDashboard
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.bar as Bar

MouseArea {
    id: root
    property bool alwaysShowAllResources: false
    implicitHeight: columnLayout.implicitHeight
    implicitWidth: columnLayout.implicitWidth
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    // Left-click opens the system dashboard
    acceptedButtons: Qt.LeftButton
    onClicked: event => {
        if (event.button === Qt.LeftButton)
            GlobalStates.systemDashboardOpen = !GlobalStates.systemDashboardOpen
    }

    Component.onCompleted: ResourceUsage.keepAlive()
    Component.onDestruction: ResourceUsage.releaseKeepAlive()

    ColumnLayout {
        id: columnLayout
        spacing: 10
        anchors.fill: parent

        Resource {
            Layout.alignment: Qt.AlignHCenter
            iconName: "memory"
            percentage: ResourceUsage.memoryUsedPercentage
            shown: Config.options?.bar?.resources?.showMemoryIndicator ?? true
            warningThreshold: Config.options?.bar?.resources?.memoryWarningThreshold ?? 90
        }

        Resource {
            Layout.alignment: Qt.AlignHCenter
            iconName: "swap_horiz"
            percentage: ResourceUsage.swapUsedPercentage
            shown: Config.options?.bar?.resources?.showSwapIndicator ?? true
            warningThreshold: Config.options?.bar?.resources?.swapWarningThreshold ?? 90
        }

        Resource {
            Layout.alignment: Qt.AlignHCenter
            iconName: "planner_review"
            percentage: ResourceUsage.cpuUsage
            shown: Config.options?.bar?.resources?.showCpuIndicator ?? true
            warningThreshold: Config.options?.bar?.resources?.cpuWarningThreshold ?? 90
        }

        Resource {
            Layout.alignment: Qt.AlignHCenter
            iconName: "memory_alt"
            percentage: ResourceUsage.gpuUsage
            shown: Config.options?.bar?.resources?.showGpuIndicator ?? true
            warningThreshold: Config.options?.bar?.resources?.gpuWarningThreshold ?? 90
        }

    }

    // Slides out of this widget and stays next to it. Supersedes the old hover
    // ResourcesPopup, which showed a subset of the same readouts.
    BarAnchoredPanel {
        anchorItem: root
        anchorWindow: root.QsWindow.window
        pinned: GlobalStates.systemDashboardOpen
        anchorHovered: root.containsMouse
        popupNamespace: "quickshell:systemDashboard"
        onCloseRequested: GlobalStates.systemDashboardOpen = false
        contentComponent: SystemDashboardContent {}
    }
}
