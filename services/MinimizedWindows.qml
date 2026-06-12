pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.modules.common
import qs.services

/**
 * Service to manage "minimized" windows.
 * Niri: windows are moved to a far-away workspace (no native minimize).
 * Hyprland: windows are moved to the special:minimized workspace.
 */
Singleton {
    id: root

    // Workspace index used for minimized windows (high number to stay out of the way)
    readonly property int minimizedWorkspaceIndex: 99
    
    // Map of minimized windows: windowId -> { appId, title, originalWorkspace }
    property var minimizedWindows: ({})
    
    // List of minimized window IDs for easy iteration
    // (Niri numeric ids or Hyprland address strings)
    property var minimizedIds: []
    
    // Check if a window is minimized
    function isMinimized(windowId) {
        return minimizedIds.includes(windowId);
    }
    
    // Get minimized windows for a specific app
    function getMinimizedForApp(appId) {
        const pattern = appId.toLowerCase();
        return minimizedIds.filter(id => {
            const info = minimizedWindows[id];
            return info && info.appId.toLowerCase().includes(pattern);
        });
    }
    
    // Count minimized windows for an app
    function countMinimizedForApp(appId) {
        return getMinimizedForApp(appId).length;
    }
    
    // Minimize the focused window or a specific window
    function minimize(windowId = null) {
        if (CompositorService.isHyprland) {
            minimizeHyprland(windowId);
            return;
        }
        if (!CompositorService.isNiri) return;
        
        // Get window info
        let targetWindow;
        if (windowId) {
            targetWindow = NiriService.windows?.find(w => w.id === windowId);
        } else {
            targetWindow = NiriService.activeWindow;
            windowId = targetWindow?.id;
        }
        
        if (!targetWindow || !windowId) return;
        
        // Don't minimize the main quickshell shell (but allow settings window)
        // Skip this check for now - allow all windows to be minimized
        
        // Already minimized?
        if (isMinimized(windowId)) return;
        
        // Store window info
        const info = {
            appId: targetWindow.app_id || "",
            title: targetWindow.title || "",
            originalWorkspace: NiriService.focusedWorkspaceIndex
        };
        
        minimizedWindows[windowId] = info;
        minimizedIds = [...minimizedIds, windowId];
        
        // Move to a workspace far to the right (Niri will create it)
        const allWorkspaces = NiriService.allWorkspaces ?? [];
        const maxWsIndex = allWorkspaces.length > 0 
            ? Math.max(...allWorkspaces.map(ws => ws.idx), 1) 
            : 1;
        const targetWs = maxWsIndex + 10;
        
        moveToWorkspaceProc.command = [
            "niri", "msg", "action", "move-window-to-workspace",
            "--window-id", windowId.toString(),
            "--focus", "false",
            targetWs.toString()
        ];
        moveToWorkspaceProc.running = true;
    }
    
    function minimizeHyprland(windowId) {
        let targetWindow;
        if (windowId) {
            targetWindow = HyprlandData.windowList?.find(w => w.address === windowId);
        } else {
            targetWindow = HyprlandData.windowList?.find(w => w.focusHistoryID === 0);
            windowId = targetWindow?.address;
        }

        if (!targetWindow || !windowId) return;
        if (isMinimized(windowId)) return;

        minimizedWindows[windowId] = {
            appId: targetWindow.class || "",
            title: targetWindow.title || "",
            originalWorkspace: targetWindow.workspace?.id ?? 1
        };
        minimizedIds = [...minimizedIds, windowId];

        CompositorService.hyprDispatch(`movetoworkspacesilent special:minimized,address:${windowId}`);
    }

    function restoreHyprland(windowId) {
        if (!isMinimized(windowId)) return;
        const info = minimizedWindows[windowId];
        if (!info) return;

        delete minimizedWindows[windowId];
        minimizedIds = minimizedIds.filter(id => id !== windowId);

        // Match Niri behavior: restore onto the currently focused workspace
        const targetWorkspace = HyprlandData.activeWorkspace?.id ?? info.originalWorkspace ?? 1;
        CompositorService.hyprDispatch(`movetoworkspacesilent ${targetWorkspace},address:${windowId}`);
        CompositorService.hyprDispatch(`focuswindow address:${windowId}`);
    }

    // Restore a minimized window
    function restore(windowId) {
        if (CompositorService.isHyprland) {
            restoreHyprland(windowId);
            return;
        }
        if (!CompositorService.isNiri) return;
        if (!isMinimized(windowId)) return;
        
        const info = minimizedWindows[windowId];
        if (!info) return;
        
        // Remove from minimized list
        delete minimizedWindows[windowId];
        minimizedIds = minimizedIds.filter(id => id !== windowId);
        
        // Move back to current workspace and focus
        const targetWorkspace = NiriService.focusedWorkspaceIndex;
        
        restoreProc.command = [
            "niri", "msg", "action", "move-window-to-workspace",
            "--window-id", windowId.toString(),
            targetWorkspace.toString()
        ];
        restoreProc.running = true;
    }
    
    // Restore all minimized windows for an app
    function restoreApp(appId) {
        const windowIds = getMinimizedForApp(appId);
        for (const id of windowIds) {
            restore(id);
        }
    }
    
    // Restore the most recently minimized window for an app
    function restoreLatestForApp(appId) {
        const windowIds = getMinimizedForApp(appId);
        if (windowIds.length > 0) {
            restore(windowIds[windowIds.length - 1]);
        }
    }
    
    Process {
        id: moveToWorkspaceProc
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                console.warn("[MinimizedWindows] Failed to move window");
            }
        }
    }
    
    Process {
        id: restoreProc
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                // Focus the window after moving
                Qt.callLater(() => {
                    const windowId = parseInt(restoreProc.command[5]);
                    NiriService.focusWindow(windowId);
                });
            }
        }
    }
    
    // IPC handler for external control
    IpcHandler {
        target: "minimize"
        
        function minimize(): void {
            root.minimize();
        }
        
        function restore(windowId: var): void {
            root.restore(windowId);
        }
    }
}
