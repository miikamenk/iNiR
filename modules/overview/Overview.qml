import qs
import qs.services
import qs.services.deferred
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: overviewScope
    property bool dontAutoCancelSearch: false

    Component.onCompleted: CompositorService.setSortingConsumer("overview", GlobalStates.overviewOpen)
    Variants {
        id: overviewVariants
        model: Quickshell.screens
        PanelWindow {
            id: root
            required property var modelData
            property bool _presentedOpen: false
            property string searchingText: ""
            readonly property HyprlandMonitor monitor: CompositorService.isHyprland ? Hyprland.monitorFor(root.screen) : null
            property bool monitorIsFocused: CompositorService.isHyprland 
                ? (Hyprland.focusedMonitor?.id == monitor?.id)
                : (NiriService.currentOutput === root.screen?.name)
            readonly property bool activeScreenOnly: Config.options?.overview?.activeScreenOnly ?? false
            readonly property bool shouldShow: GlobalStates.overviewOpen && (!activeScreenOnly || monitorIsFocused)
            screen: modelData

            Component.onCompleted: {
                visible = root.shouldShow
                if (root.shouldShow) {
                    Qt.callLater(() => { root._presentedOpen = root.shouldShow })
                    Qt.callLater(() => {
                        const prefix = GlobalStates.overviewSearchPrefix
                        if (prefix.length > 0) {
                            overviewScope.dontAutoCancelSearch = true
                            root.setSearchingText(prefix)
                        } else {
                            searchWidget.cancelSearch()
                        }
                        searchWidget.focusSearchInput()
                        root.maybeSwitchWorkspaceOnOpen()
                        delayedGrabTimer.start()
                    })
                }
            }

            onShouldShowChanged: {
                if (shouldShow)
                    Qt.callLater(() => { root._presentedOpen = root.shouldShow })
                else
                    root._presentedOpen = false
            }

            Connections {
                target: root
                function onShouldShowChanged() {
                    if (root.shouldShow) {
                        _overviewCloseTimer.stop()
                        root.visible = true
                    } else {
                        _overviewCloseTimer.restart()
                    }
                }
            }

            Timer {
                id: _overviewCloseTimer
                // Cover the full exit animation (elementMoveExit scales with the
                // enterExit speed setting) plus a small margin so the window is
                // never torn down mid-close.
                interval: (Appearance.animation.elementMoveExit.duration + 40)
                onTriggered: root.visible = false
            }

            exclusionMode: ExclusionMode.Ignore

            WlrLayershell.namespace: "quickshell:overview"
            WlrLayershell.layer: WlrLayer.Overlay
            // Keyboard focus only on the monitor that should show
            WlrLayershell.keyboardFocus: root.shouldShow && !GlobalStates.regionSelectorOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            color: "transparent"

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            // Scrim de fondo: oscurece todo detrás del overview mientras está activo
            Rectangle {
                anchors.fill: parent
                z: -1
                color: {
                    const ov = Config.options?.overview ?? null
                    const v = (ov && ov.scrimDim !== undefined) ? ov.scrimDim : 35
                    const clamped = Math.max(0, Math.min(100, v))
                    const a = clamped / 100
                    return ColorUtils.transparentize(Appearance.colors.colLayer0Base, 1 - a)
                }
                opacity: root._presentedOpen ? 1 : 0
                visible: opacity > 0.001

                // The scrim fades a little slower than the content on the way out, so
                // the dimmed backdrop lingers under the dissolving panel instead of
                // snapping the desktop back before the surface has left.
                Behavior on opacity {
                    enabled: Appearance.animationsEnabled
                    animation: NumberAnimation {
                        duration: root._presentedOpen
                            ? Appearance.animation.elementMoveEnter.duration
                            : Appearance.animation.elementMoveExit.duration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: root._presentedOpen
                            ? Appearance.animationCurves.standardDecel
                            : Appearance.animationCurves.standardAccel
                    }
                }
            }

            MouseArea {
                id: backdropClickArea
                anchors.fill: parent
                onClicked: mouse => {
                    // Cierra solo si el click es fuera del contenido visible
                    // Check against searchWidget and overviewLoader, not columnLayout
                    // because columnLayout fills the whole window height
                    const searchPos = mapToItem(searchWidget, mouse.x, mouse.y)
                    const inSearch = searchPos.x >= 0 && searchPos.x <= searchWidget.width &&
                                     searchPos.y >= 0 && searchPos.y <= searchWidget.height
                    
                    const overviewPos = overviewLoader.item ? mapToItem(overviewLoader.item, mouse.x, mouse.y) : null
                    const inOverview = overviewLoader.item && overviewPos &&
                                       overviewPos.x >= 0 && overviewPos.x <= overviewLoader.item.width &&
                                       overviewPos.y >= 0 && overviewPos.y <= overviewLoader.item.height

                    const dashPos = dashboardPanel.visible ? mapToItem(dashboardPanel, mouse.x, mouse.y) : null
                    const inDashboard = dashboardPanel.visible && dashPos &&
                                        dashPos.x >= 0 && dashPos.x <= dashboardPanel.width &&
                                        dashPos.y >= 0 && dashPos.y <= dashboardPanel.height

                    const allAppsPos = allAppsGridLoader.item ? mapToItem(allAppsGridLoader.item, mouse.x, mouse.y) : null
                    const inAllApps = allAppsGridLoader.item && allAppsPos &&
                                      allAppsPos.x >= 0 && allAppsPos.x <= allAppsGridLoader.item.width &&
                                      allAppsPos.y >= 0 && allAppsPos.y <= allAppsGridLoader.item.height
                    
                    if (!inSearch && !inOverview && !inDashboard && !inAllApps) {
                        GlobalStates.overviewOpen = false
                    }
                }
            }

            // Focus grab for Hyprland (doesn't work on Niri)
            CompositorFocusGrab {
                id: grab
                windows: [root]
                property bool canBeActive: root.monitorIsFocused
                active: false
                onCleared: () => {
                    if (!active)
                        GlobalStates.overviewOpen = false;
                }
            }
            
            // For Niri: detect window focus changes to close overview (if configured)
            Connections {
                target: CompositorService.isNiri ? NiriService : null
                enabled: CompositorService.isNiri
                function onActiveWindowChanged() {
                    // Respect keepOverviewOpenOnWindowClick setting
                    const keepOpen = Config.options?.overview?.keepOverviewOpenOnWindowClick ?? true;
                    // If a window gets focus while overview is open, close it only if not configured to keep open
                    if (GlobalStates.overviewOpen && NiriService.activeWindow && !keepOpen) {
                        GlobalStates.overviewOpen = false;
                    }
                }
            }

            Connections {
                target: GlobalStates
                function onOverviewOpenChanged() {
                    CompositorService.setSortingConsumer("overview", GlobalStates.overviewOpen)
                    if (!GlobalStates.overviewOpen) {
                        // Al cerrar, limpiar completamente la búsqueda
                        searchWidget.cancelSearch();
                        searchWidget.disableExpandAnimation();
                        overviewScope.dontAutoCancelSearch = false;
                        GlobalStates.overviewSearchPrefix = "";
                    } else {
                        if (!overviewScope.dontAutoCancelSearch) {
                            searchWidget.cancelSearch();
                        }
                        // Al abrir, garantizar foco en el campo de búsqueda
                        Qt.callLater(() => searchWidget.focusSearchInput());
                        root.maybeSwitchWorkspaceOnOpen();
                        delayedGrabTimer.start();
                    }
                }
            }

            Timer {
                id: delayedGrabTimer
                interval: Config.options.hacks.arbitraryRaceConditionDelay
                repeat: false
                onTriggered: {
                    if (!grab.canBeActive)
                        return;
                    grab.active = GlobalStates.overviewOpen;
                }
            }

            implicitWidth: columnLayout.implicitWidth
            implicitHeight: columnLayout.implicitHeight

            function setSearchingText(text) {
                searchWidget.setSearchingText(text);
                searchWidget.focusFirstItem();
            }

            function maybeSwitchWorkspaceOnOpen() {
                const ov = Config.options?.overview ?? null;
                if (!ov || !ov.switchToWorkspaceOnOpen || !ov.switchWorkspaceIndex || ov.switchWorkspaceIndex <= 0)
                    return;

                if (CompositorService.isNiri) {
                    const screenName = root.modelData && root.modelData.name;
                    if (!screenName || screenName !== NiriService.currentOutput)
                        return;
                    const targetIdx = ov.switchWorkspaceIndex;
                    if (!targetIdx || targetIdx <= 0)
                        return;
                    NiriService.switchToWorkspace(targetIdx);
                } else if (CompositorService.isHyprland) {
                    if (!root.monitorIsFocused)
                        return;
                    const wsNumber = ov.switchWorkspaceIndex;
                    CompositorService.hyprDispatch(`workspace ${wsNumber}`);
                }
            }

            Column {
                id: columnLayout

                // Shell desaturation effect
                layer.enabled: Appearance.shouldDesaturate("overlays") && columnLayout.visible
                layer.effect: ShellDesaturationEffect {}

                // One 0..1 driver so the surface unfolds as a single coherent morph.
                // Enter rides the per-style spatial spring (elementMoveEnter branches:
                // cookieSpring bounce, zzzOvershoot punch, emphasizedDecel glide), so
                // each worldview opens in its own character and the overshoot past 1
                // becomes a subtle settle on the anisotropic scale. Exit is a clean
                // decel: it moves decisively at the start and eases into closed, and
                // because opacity leads OUT (below) the slow tail is already invisible
                // — the surface dissolves upward toward the search bar instead of
                // visibly squishing to nothing, which is what made the old close ugly.
                readonly property int motionDuration: root._presentedOpen
                    ? Appearance.animation.elementMoveEnter.duration
                    : Appearance.animation.elementMoveExit.duration
                readonly property var motionCurve: root._presentedOpen
                    ? Appearance.animation.elementMoveEnter.bezierCurve
                    : Appearance.animationCurves.emphasizedDecel
                property real openProgress: root._presentedOpen ? 1 : 0

                // Direction-aware opacity. Open: leads in, fully legible by 70% of the
                // unfold. Close: leads out, fully faded by the time the surface has
                // receded ~45%, so the slow decel tail collapses invisibly.
                opacity: root._presentedOpen
                    ? Math.min(1, openProgress / 0.7)
                    : Math.max(0, (openProgress - 0.45) / 0.55)
                visible: openProgress > 0.001

                transform: [
                    Scale {
                        origin.x: columnLayout.width / 2
                        origin.y: 0
                        // Gentle anisotropy — the vertical axis travels a touch further
                        // than the horizontal so the panel reads as unfolding from the
                        // search bar downward, without the heavy squish of a big yScale.
                        xScale: 0.975 + 0.025 * columnLayout.openProgress
                        yScale: 0.93 + 0.07 * columnLayout.openProgress
                    },
                    // Recede toward the search-bar anchor at the top.
                    Translate { y: (1 - columnLayout.openProgress) * -12 }
                ]

                Behavior on openProgress {
                    enabled: Appearance.animationsEnabled
                    NumberAnimation {
                        duration: columnLayout.motionDuration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: columnLayout.motionCurve
                    }
                }
                
                // Always center the overview vertically - this is the default behavior.
                // Never use verticalCenter anchor with dynamic Column - causes blur and erratic positioning.
                // Use top anchor with calculated topMargin to center instead.
                
                anchors {
                    horizontalCenter: parent.horizontalCenter
                    top: parent.top
                    topMargin: {
                        const ov = Config?.options?.overview;
                        const respectBar = ov && ov.respectBar !== undefined ? ov.respectBar : true;
                        
                        // Calculate bar/dock offset at top
                        let barOffset = 0;
                        if (respectBar && !(Config.options?.bar?.bottom ?? false)) {
                            barOffset = Appearance.sizes.barHeight + Appearance.rounding.screenRounding;
                        }
                        const dock = Config.options?.dock;
                        if (dock?.enable && dock?.position === "top") {
                            barOffset += (dock.height ?? 60) + 20;
                        }
                        
                        // Calculate bar/dock offset at bottom
                        let bottomOffset = 8;
                        if (respectBar && (Config.options?.bar?.bottom ?? false)) {
                            bottomOffset += Appearance.sizes.barHeight + Appearance.rounding.screenRounding;
                        }
                        if (dock?.enable && dock?.position === "bottom") {
                            bottomOffset += (dock.height ?? 60) + 20;
                        }
                        
                        // Center the content vertically in available space
                        const availableHeight = root.height - barOffset - bottomOffset;
                        const contentHeight = columnLayout.implicitHeight;
                        // Round to avoid subpixel positioning that causes blur
                        const centeredMargin = barOffset + Math.round(Math.max(0, (availableHeight - contentHeight) / 2));
                        return centeredMargin;
                    }
                }
                spacing: -8


                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) {
                        GlobalStates.overviewOpen = false;
                    } else if (event.key === Qt.Key_Left) {
                        if (!root.searchingText) {
                            if (CompositorService.isNiri) {
                                // Niri uses a 1-based idx for workspaces on the monitor.
                                const currentIdx = NiriService.getCurrentWorkspaceNumber();
                                const targetIdx = currentIdx - 1;
                                if (targetIdx >= 1)
                                    NiriService.switchToWorkspace(targetIdx);
                            } else {
                                CompositorService.hyprDispatch("workspace r-1");
                            }
                        }
                    } else if (event.key === Qt.Key_Right) {
                        if (!root.searchingText) {
                            if (CompositorService.isNiri) {
                                const currentIdx = NiriService.getCurrentWorkspaceNumber();
                                const targetIdx = currentIdx + 1;
                                NiriService.switchToWorkspace(targetIdx);
                            } else {
                                CompositorService.hyprDispatch("workspace r+1");
                            }
                        }
                    }
                }

                SearchWidget {
                    id: searchWidget
                    anchors.horizontalCenter: parent.horizontalCenter
                    searchingText: root.searchingText
                    panelVisible: root.visible
                    // Centered mode: limit search results to 60% of screen height
                    availableHeight: Math.max(220, root.height * 0.6)
                    onSearchingTextChanged: if (searchingText !== root.searchingText) root.searchingText = searchingText
                }

                Loader {
                    id: overviewLoader
                    anchors.horizontalCenter: parent.horizontalCenter
                    readonly property bool dashboardMode: Config.options?.overview?.dashboard?.enable ?? false
                    readonly property bool allAppsGridEnabled: Config.options?.overview?.allAppsGrid ?? false
                    active: GlobalStates.overviewOpen && !dashboardMode && !allAppsGridEnabled && (Config.options?.overview?.enable ?? true)
                    visible: active && (root.searchingText == "")
                    sourceComponent: CompositorService.isNiri ? niriComponent : hyprComponent
                }

                Loader {
                    id: allAppsGridLoader
                    anchors.horizontalCenter: parent.horizontalCenter
                    readonly property bool allAppsEnabled: Config.options?.overview?.allAppsGrid ?? false
                    readonly property bool dashboardMode: Config.options?.overview?.dashboard?.enable ?? false
                    active: GlobalStates.overviewOpen && allAppsEnabled && !dashboardMode
                    visible: active && (root.searchingText == "")
                    sourceComponent: allAppsGridComponent
                }

                Component {
                    id: hyprComponent
                    OverviewWidget {
                        panelWindow: root
                        visible: (root.searchingText == "")
                    }
                }

                Component {
                    id: niriComponent
                    OverviewNiriWidget {
                        panelWindow: root
                        visible: (root.searchingText == "")
                    }
                }

                Component {
                    id: allAppsGridComponent
                    OverviewAllAppsGrid {
                        panelVisible: root.visible
                        availableHeight: Math.max(400, root.height * 0.78)
                        onAppLaunched: GlobalStates.overviewOpen = false
                    }
                }

                // Dashboard panel below workspace thumbnails
                OverviewDashboard {
                    id: dashboardPanel
                    anchors.horizontalCenter: parent.horizontalCenter
                    panelVisible: root.visible
                    visible: (root.searchingText == "") && (Config.options?.overview?.dashboard?.enable ?? false)
                    opacity: root._presentedOpen ? 1 : 0

                    Behavior on opacity {
                        enabled: Appearance.animationsEnabled
                        NumberAnimation {
                            duration: Appearance.animation?.elementMoveEnter?.duration ?? 400
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Appearance.animationCurves?.emphasizedDecel ?? [0.05, 0.7, 0.1, 1, 1, 1]
                        }
                    }
                }
            }
        }
    }

}
