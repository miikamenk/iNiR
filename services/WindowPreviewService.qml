pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.services.deferred
import qs.modules.common
import qs.modules.common.functions

/**
 * WindowPreviewService - Window preview caching for TaskView
 * 
 * Strategy:
 * - Capture previews ONLY when TaskView opens
 * - Cache in ~/.cache/inir/window-previews/
 * - Only capture windows that don't have a recent preview
 * - Clean up on window close
 */
Singleton {
    id: root

    // Niri: niri msg screenshot-window (any window). Hyprland: grim region capture
    // (only windows on visible workspaces; stale previews are kept for the rest).
    readonly property bool available: CompositorService.isNiri || CompositorService.isHyprland

    function _log(...args): void {
        if (Quickshell.env("QS_DEBUG") === "1") console.log(...args);
    }

    readonly property string previewDir: FileUtils.trimFileProtocol(Directories.genericCache) + "/inir/window-previews"
    
    // Map of windowId -> { path, timestamp }
    property var previewCache: ({})
    
    property bool initialized: false
    property bool capturing: false
    
    // Preview validity duration (5 minutes)
    readonly property int previewValidityMs: 300000

    // Debounce: coalesce rapid capture requests (e.g. hovering across multiple dock icons)
    Timer {
        id: captureDebounceTimer
        interval: 100  // 100ms debounce — fast enough to feel instant, slow enough to coalesce
        repeat: false
        onTriggered: root._doCapture()
    }
    // Cooldown: prevent captures from firing back-to-back after one completes
    property double _lastCaptureEndTime: 0
    readonly property int _captureCooldownMs: 2000  // 2 seconds between capture cycles
    
    signal captureComplete()
    // windowId is a Niri numeric id or a Hyprland address string
    signal previewUpdated(var windowId)

    // Current window ids in the compositor's terms (Niri ids / Hyprland addresses)
    function _allWindowIds() {
        if (CompositorService.isHyprland)
            return (HyprlandData.windowList ?? []).map(w => w.address)
        return (NiriService.windows ?? []).map(w => w.id)
    }

    // Ids of windows that can actually be captured right now.
    // On Hyprland only windows on a visible (active/special) workspace can be
    // grabbed via grim; everything is capturable on Niri.
    function _capturableWindowIds() {
        if (!CompositorService.isHyprland)
            return _allWindowIds()
        const visibleWs = new Set()
        for (const mon of (HyprlandData.monitors ?? [])) {
            if (mon.activeWorkspace?.id !== undefined)
                visibleWs.add(mon.activeWorkspace.id)
            if (mon.specialWorkspace?.id)
                visibleWs.add(mon.specialWorkspace.id)
        }
        return (HyprlandData.windowList ?? [])
            .filter(w => w.mapped !== false && w.hidden !== true && visibleWs.has(w.workspace?.id))
            .map(w => w.address)
    }

    Component.onCompleted: {
        // Lazy init: only when TaskView actually requests previews.
    }
    
    function initialize(): void {
        if (initialized) return
        initialized = true
        ensureDirProcess.running = true
    }
    
    Process {
        id: ensureDirProcess
        command: ["/usr/bin/mkdir", "-p", root.previewDir]
        onExited: scanProcess.running = true
    }
    
    Process {
        id: scanProcess
        command: ["/usr/bin/ls", "-1", root.previewDir]
        stdout: SplitParser {
            onRead: data => {
                const filename = data.trim()
                // Niri ids are numeric, Hyprland addresses look like 0xabcdef
                const match = filename.match(/^window-(\d+|0x[0-9a-fA-F]+)\.png$/)
                if (match) {
                    const id = match[1].startsWith("0x") ? match[1] : parseInt(match[1])
                    root.previewCache[id] = {
                        path: root.previewDir + "/" + filename,
                        timestamp: Date.now()
                    }
                }
            }
        }
        onExited: {
            _log("[WindowPreviewService] Loaded", Object.keys(root.previewCache).length, "cached previews")
            root.cleanupOrphans()
        }
    }
    
    // Remove previews for windows that no longer exist
    function cleanupOrphans(): void {
        // previewCache keys are strings; compare in string space for both compositors
        const windowIds = new Set(_allWindowIds().map(id => String(id)))

        const toDelete = []
        for (const id in previewCache) {
            if (!windowIds.has(String(id))) {
                toDelete.push(id)
            }
        }
        
        if (toDelete.length > 0) {
            for (const id of toDelete) {
                delete previewCache[id]
            }
            previewCache = Object.assign({}, previewCache)
            
            // Delete files
            const cmd = ["/usr/bin/rm", "-f"]
            for (const id of toDelete) {
                cmd.push(root.previewDir + "/window-" + id + ".png")
            }
            Quickshell.execDetached(cmd)
        }
    }

    // Track if we've done initial capture this session
    property bool initialCapturesDone: false
    
    // Called when TaskView/dock preview opens - debounced to coalesce rapid hover events
    function captureForTaskView(): void {
        if (!initialized) initialize()

        // Always emit captureComplete immediately so cached previews show instantly
        root.captureComplete()

        if (capturing) return

        // Cooldown: don't re-capture if we just finished one
        if (Date.now() - _lastCaptureEndTime < _captureCooldownMs && initialCapturesDone) {
            return
        }

        captureDebounceTimer.restart()
    }

    function _baseCaptureCommand(): var {
        if (CompositorService.isHyprland)
            return ["/usr/bin/bash", Quickshell.shellPath("scripts/capture-windows-hypr.sh")]
        return ShellExec.supportsFish()
            ? ["/usr/bin/fish", Quickshell.shellPath("scripts/capture-windows.fish")]
            : ["/usr/bin/bash", Quickshell.shellPath("scripts/capture-windows.sh")]
    }

    function _beginCapture(): void {
        capturing = true
        // grim writes straight to file; only niri screenshot-window touches the clipboard
        if (CompositorService.isNiri)
            Cliphist.suppressRefresh = true
    }

    // Internal: actual capture logic, called after debounce
    function _doCapture(): void {
        if (capturing) return

        const candidates = _capturableWindowIds()
        if (candidates.length === 0) return

        const now = Date.now()
        const idsToCapture = []

        for (const id of candidates) {
            const cached = previewCache[id]
            // Capture if: no preview or preview is stale
            const needsCapture = !cached ||
                                 (now - cached.timestamp) > previewValidityMs
            if (needsCapture) {
                idsToCapture.push(id)
            }
        }

        if (idsToCapture.length === 0) {
            root.captureComplete()
            return
        }

        _log("[WindowPreviewService] Capturing", idsToCapture.length, "windows")
        initialCapturesDone = true
        _beginCapture()

        // Build command with IDs
        const cmd = _baseCaptureCommand()
        for (const id of idsToCapture) {
            cmd.push(id.toString())
        }

        captureProcess.idsToCapture = idsToCapture
        captureProcess.command = cmd
        captureProcess.running = true
    }

    // Capture ALL windows (force refresh)
    function captureAllWindows(): void {
        if (capturing) return

        if (!initialized) initialize()

        const ids = _capturableWindowIds()
        if (ids.length === 0) return

        _log("[WindowPreviewService] Force capturing all", ids.length, "windows")
        _beginCapture()

        const cmd = _baseCaptureCommand()
        cmd.push("--all")
        for (const id of ids) {
            cmd.push(id.toString())
        }
        captureProcess.idsToCapture = ids
        captureProcess.command = cmd
        captureProcess.running = true
    }
    
    Process {
        id: captureProcess
        property var idsToCapture: []

        stdout: SplitParser {
            onRead: (line) => _log("[WindowPreviewService:capture]", line)
        }
        stderr: SplitParser {
            onRead: (line) => _log("[WindowPreviewService:capture][err]", line)
        }
        
        onExited: (exitCode, exitStatus) => {
            root.capturing = false
            root._lastCaptureEndTime = Date.now()

            if (exitCode !== 0) {
                console.log("[WindowPreviewService] capture process failed", exitCode, exitStatus)
            } else {
                const timestamp = Date.now()
                for (const id of idsToCapture) {
                    const path = root.previewDir + "/window-" + id + ".png"
                    root.previewCache[id] = {
                        path: path,
                        timestamp: timestamp
                    }
                    root.previewUpdated(id)
                }
                root.previewCache = Object.assign({}, root.previewCache)
            }
            
            idsToCapture = []
            // The capture script has already removed only its own entries and
            // conditionally restored the clipboard before returning.
            if (CompositorService.isNiri) {
                Cliphist.suppressRefresh = false
                Cliphist.refresh()
            }
            root.captureComplete()
        }
    }

    // Clean up when window closes
    Connections {
        target: NiriService
        enabled: root.initialized && CompositorService.isNiri

        function onWindowsChanged(): void {
            cleanupTimer.restart()
        }
    }

    Connections {
        target: HyprlandData
        enabled: root.initialized && CompositorService.isHyprland

        function onWindowListChanged(): void {
            cleanupTimer.restart()
        }
    }
    
    Timer {
        id: cleanupTimer
        interval: 1000
        onTriggered: root.cleanupOrphans()
    }
    
    // Public API — windowId is a Niri numeric id or a Hyprland address string
    function getPreviewUrl(windowId: var): string {
        const cached = previewCache[windowId]
        if (!cached) return ""
        return "file://" + cached.path + "?" + cached.timestamp
    }

    function hasPreview(windowId: var): bool {
        return previewCache[windowId] !== undefined
    }
    
    function clearPreviews(): void {
        Quickshell.execDetached(["/usr/bin/rm", "-rf", previewDir])
        previewCache = {}
    }
}
