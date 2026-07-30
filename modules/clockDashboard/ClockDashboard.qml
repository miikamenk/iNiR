pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Clock dashboard — large animated clock, calendar, upcoming events, weather.
//
// The panel itself lives inside the bar clock widget (see bar/ClockWidget.qml and
// verticalBar/VerticalClockWidget.qml) so it can anchor to it and slide out of it.
// Only one bar family is ever loaded, so only one instance exists. This scope
// keeps the IPC surface and global shortcut, both of which drive
// GlobalStates.clockDashboardOpen — the panel's pinned state.
Scope {
    id: root

    IpcHandler {
        target: "clockDashboard"

        function toggle(): void {
            GlobalStates.clockDashboardOpen = !GlobalStates.clockDashboardOpen
        }

        function close(): void {
            GlobalStates.clockDashboardOpen = false
        }

        function open(): void {
            GlobalStates.clockDashboardOpen = true
        }
    }

    Loader {
        active: CompositorService.isHyprland
        sourceComponent: GlobalShortcut {
            name: "clockDashboardToggle"
            description: "Toggles clock dashboard on press"

            onPressed: {
                GlobalStates.clockDashboardOpen = !GlobalStates.clockDashboardOpen
            }
        }
    }
}
