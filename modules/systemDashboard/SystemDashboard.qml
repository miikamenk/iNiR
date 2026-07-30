pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// System dashboard — CPU, RAM, GPU, VRAM, network, disk, temperatures,
// and historical usage.
//
// The panel itself lives inside the bar resources widget (see bar/Resources.qml and
// verticalBar/Resources.qml) so it can anchor to it and slide out of it. Only one
// bar family is ever loaded, so only one instance exists. This scope keeps the IPC
// surface and global shortcut, both of which drive
// GlobalStates.systemDashboardOpen — the panel's pinned state.
Scope {
    id: root

    IpcHandler {
        target: "systemDashboard"

        function toggle(): void {
            GlobalStates.systemDashboardOpen = !GlobalStates.systemDashboardOpen
        }

        function close(): void {
            GlobalStates.systemDashboardOpen = false
        }

        function open(): void {
            GlobalStates.systemDashboardOpen = true
        }
    }

    Loader {
        active: CompositorService.isHyprland
        sourceComponent: GlobalShortcut {
            name: "systemDashboardToggle"
            description: "Toggles system dashboard on press"

            onPressed: {
                GlobalStates.systemDashboardOpen = !GlobalStates.systemDashboardOpen
            }
        }
    }
}
