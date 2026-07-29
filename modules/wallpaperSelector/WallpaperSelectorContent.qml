import qs
import qs.services
import qs.services.deferred
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects as GE
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

MouseArea {
    id: root
    readonly property bool previewPaneVisible: Config.options?.wallpaperSelector?.showPreviewPane ?? true
    // Fewer, larger cells when the hero pane is eating horizontal space.
    property int columns: root.previewPaneVisible ? 3 : 4
    property real previewCellAspectRatio: 4 / 3
    property bool useDarkMode: Appearance.m3colors.darkmode
    property string _lastThumbnailSizeName: ""
    readonly property real _dpr: root.window ? root.window.devicePixelRatio : 1

    // ------------------------------------------------------------------
    // Highlight tracking — what the hero pane and live preview follow.
    // Hover and keyboard navigation both funnel into grid.currentIndex.
    // ------------------------------------------------------------------
    // Path and directory-ness travel together in one object. Splitting them into
    // two properties let consumers observe a half-updated pair — briefly pairing a
    // folder's path with isDir:false, which made the hero pane try to decode a
    // directory as an image.
    property var _highlight: ({
        path: "",
        isDir: false
    })
    readonly property string highlightPath: root._highlight.path
    readonly property bool highlightIsDir: root._highlight.isDir

    function syncHighlight(): void {
        const model = Wallpapers.folderModel;
        const index = grid.currentIndex;
        if (!model || index < 0 || index >= model.count) {
            root._highlight = {
                path: "",
                isDir: false
            };
            return;
        }
        root._highlight = {
            path: FileUtils.trimFileProtocol(String(model.get(index, "filePath") ?? "")),
            isDir: model.get(index, "fileIsDir") === true
        };
    }

    // ------------------------------------------------------------------
    // Live theme preview — recolours the shell from the highlighted image
    // without committing it as the wallpaper. Reverted on close unless the
    // user actually applies something.
    // ------------------------------------------------------------------
    property bool livePreviewEnabled: Config.options?.wallpaperSelector?.livePreview ?? false
    property bool _livePreviewDirty: false
    property string _originalPreviewSource: ""

    function toggleLivePreview(): void {
        const next = !root.livePreviewEnabled;
        Config.setNestedValue("wallpaperSelector.livePreview", next);
        if (next)
            livePreviewTimer.restart();
        else {
            livePreviewTimer.stop();
            root.revertLivePreview();
        }
    }

    function revertLivePreview(): void {
        if (!root._livePreviewDirty)
            return;
        root._livePreviewDirty = false;
        Config.setNestedValue("appearance.wallpaperTheming.previewSourcePath", root._originalPreviewSource);
        // Give the config write timer a beat to land before regenerating, so the
        // palette is rebuilt from the real wallpaper and not the stale preview.
        revertTimer.restart();
    }

    Timer {
        id: livePreviewTimer
        interval: Config.options?.wallpaperSelector?.livePreviewDelayMs ?? 450
        onTriggered: {
            if (!root.livePreviewEnabled || !GlobalStates.wallpaperSelectorOpen)
                return;
            if (root.highlightIsDir || root.highlightPath.length === 0)
                return;
            // Videos would need a first-frame extraction round trip; the colours
            // you'd get are the same ones the commit path generates anyway.
            if (Images.isValidVideoByName(root.highlightPath))
                return;
            root._livePreviewDirty = true;
            Wallpapers.applyColorsOnly(root.highlightPath, root.useDarkMode);
        }
    }

    Timer {
        id: revertTimer
        interval: 160
        onTriggered: ThemeService.regenerateAutoTheme()
    }

    onHighlightPathChanged: {
        if (root.livePreviewEnabled)
            livePreviewTimer.restart();
    }

    // ------------------------------------------------------------------
    // Peek — fades the panel out of the way so the live desktop is visible.
    // ------------------------------------------------------------------
    property bool peeking: false

    // ------------------------------------------------------------------
    // Cascade — the staggered entrance only runs right after the panel opens
    // or the folder changes, so delegates recycled by scrolling appear at once.
    // ------------------------------------------------------------------
    property bool cascadeActive: false
    function startCascade(): void {
        if (!Appearance.animationsEnabled)
            return;
        root.cascadeActive = true;
        cascadeTimer.restart();
    }
    Timer {
        id: cascadeTimer
        interval: 900
        onTriggered: root.cascadeActive = false
    }

    // Multi-monitor support — capture focused monitor at open time
    property string _lockedTarget: ""
    property string _capturedMonitor: ""
    readonly property bool multiMonitorActive: Config.options?.background?.multiMonitor?.enable ?? false

    readonly property string selectedMonitor: {
        if (!multiMonitorActive) return ""
        if (_lockedTarget) return _lockedTarget
        return _capturedMonitor
    }
    readonly property string currentSelectionTarget: Wallpapers.currentSelectionTarget()
    readonly property string currentSelectionPath: Wallpapers.currentWallpaperPathForTarget(currentSelectionTarget, selectedMonitor)

    function syncDirectoryToCurrentSelection() {
        const currentPath = FileUtils.trimFileProtocol(String(root.currentSelectionPath ?? ""))
        const currentDir = FileUtils.parentDirectory(currentPath)
        if (currentDir && currentDir.length > 0)
            Wallpapers.setDirectory(currentDir)
    }

    Component.onCompleted: {
        // Read target monitor from GlobalStates (set before opening, no timing issues)
        const gsTarget = GlobalStates.wallpaperSelectorTargetMonitor ?? ""
        if (gsTarget && WallpaperListener.screenNames.includes(gsTarget)) {
            _lockedTarget = gsTarget
        } else {
            // Fallback: check Config (for settings UI "Change" button via IPC)
            const configTarget = Config.options?.wallpaperSelector?.targetMonitor ?? ""
            if (configTarget && WallpaperListener.screenNames.includes(configTarget)) {
                _lockedTarget = configTarget
            } else if (CompositorService.isNiri) {
                // Last resort: capture focused monitor (may be stale if overlay already took focus)
                _capturedMonitor = NiriService.currentOutput ?? ""
            } else if (CompositorService.isHyprland) {
                _capturedMonitor = Hyprland.focusedMonitor?.name ?? ""
            }
        }
        root._originalPreviewSource = Config.options?.appearance?.wallpaperTheming?.previewSourcePath ?? ""
        Qt.callLater(() => {
            Wallpapers.searchQuery = ""
            root.syncDirectoryToCurrentSelection()
            root.updateThumbnails()
            root.syncHighlight()
            root.startCascade()
        })
    }

    Component.onDestruction: root.revertLivePreview()

    function updateThumbnails() {
        const totalImageMargin = (Appearance.sizes.wallpaperSelectorItemMargins + Appearance.sizes.wallpaperSelectorItemPadding) * 2
        let thumbnailSizeName = Images.thumbnailSizeNameForDimensions(
            Math.round((grid.cellWidth - totalImageMargin) * root._dpr),
            Math.round((grid.cellHeight - totalImageMargin) * root._dpr)
        )
        // Ensure at least "large" (256px) — "normal" (128px) is too blurry
        if (thumbnailSizeName === "normal")
            thumbnailSizeName = "large"
        root._lastThumbnailSizeName = thumbnailSizeName
        Wallpapers.generateThumbnail(thumbnailSizeName)
    }

    Connections {
        target: Wallpapers
        function onDirectoryChanged() {
            root.updateThumbnails()
        }
        function onFolderChanged() {
            // Don't sweep the selection ring across the whole grid on a folder jump.
            selectionRing.snapNext()
            root.startCascade()
        }
    }

    Connections {
        target: Wallpapers.folderModel
        function onCountChanged() {
            root.syncHighlight()
            if (!GlobalStates.wallpaperSelectorOpen) return;
            if (!root._lastThumbnailSizeName || root._lastThumbnailSizeName.length === 0) return;
        }
    }

    function handleFilePasting(event) {
        const currentClipboardEntry = Cliphist.entries[0]
        if (/^\d+\tfile:\/\/\S+/.test(currentClipboardEntry)) {
            const url = StringUtils.cleanCliphistEntry(currentClipboardEntry);
            Wallpapers.setDirectory(FileUtils.trimFileProtocol(decodeURIComponent(url)));
            event.accepted = true;
        } else {
            event.accepted = false; // No image, let text pasting proceed
        }
    }

    function selectWallpaperPath(filePath) {
        if (filePath && filePath.length > 0) {
            const normalizedPath = FileUtils.trimFileProtocol(String(filePath))
            // Committing supersedes any live preview — drop the pending revert and
            // clear the colours-only override so theming follows the real wallpaper.
            livePreviewTimer.stop();
            root._livePreviewDirty = false;
            Config.setNestedValue("appearance.wallpaperTheming.previewSourcePath", "")
            Wallpapers.applySelectionTarget(normalizedPath, Wallpapers.currentSelectionTarget(), root.useDarkMode, root.selectedMonitor);
            Config.setNestedValue("wallpaperSelector.selectionTarget", "main")
            Config.setNestedValue("wallpaperSelector.targetMonitor", "")
            GlobalStates.wallpaperSelectionTarget = "main";
            GlobalStates.wallpaperSelectorTargetMonitor = "";
            filterField.text = "";
            GlobalStates.wallpaperSelectorOpen = false;
        }
    }

    function openWallpaperLauncher(mode: string): void {
        const target = Wallpapers.currentSelectionTarget()
        const monitor = root.selectedMonitor
        GlobalStates.wallpaperSelectorOpen = false
        // Switching to the carousel makes it the active picker, mirroring the
        // launcher's own grid button.
        Config.setNestedValue("wallpaperSelector.style", "launcher")
        GlobalStates.wallpaperSelectionTarget = target
        Config.setNestedValue("wallpaperSelector.selectionTarget", target)
        GlobalStates.wallpaperSelectorTargetMonitor = monitor
        Config.setNestedValue("wallpaperSelector.targetMonitor", monitor)
        // Left-click follows the applied wallpaper's kind; right-click forces animated.
        GlobalStates.wallpaperLauncherMode = mode === "animated" ? "animated"
            : (WallpaperListener.isAnimatedPath(
                Wallpapers.currentWallpaperPathForTarget(target, monitor))
                ? "animated" : "static")
        GlobalStates.wallpaperLauncherOpen = true
    }

    acceptedButtons: Qt.LeftButton | Qt.BackButton | Qt.ForwardButton

    onClicked: mouse => {
        const localPos = mapToItem(wallpaperGridBackground, mouse.x, mouse.y);
        const outside = (localPos.x < 0 || localPos.x > wallpaperGridBackground.width
                || localPos.y < 0 || localPos.y > wallpaperGridBackground.height);
        if (outside) {
            GlobalStates.wallpaperSelectorOpen = false;
        } else {
            mouse.accepted = false;
        }
    }

    onPressed: event => {
        if (event.button === Qt.BackButton) {
            Wallpapers.navigateBack();
        } else if (event.button === Qt.ForwardButton) {
            Wallpapers.navigateForward();
        } else {
            event.accepted = false;
        }
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            GlobalStates.wallpaperSelectorOpen = false;
            event.accepted = true;
        } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_V) { // Intercept Ctrl+V to handle "paste to go to" in pickers
            root.handleFilePasting(event);
        } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_Space) {
            root.peeking = !root.peeking;
            event.accepted = true;
        } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_P) {
            root.toggleLivePreview();
            event.accepted = true;
        } else if (event.modifiers & Qt.AltModifier && event.key === Qt.Key_Up) {
            Wallpapers.navigateUp();
            event.accepted = true;
        } else if (event.modifiers & Qt.AltModifier && event.key === Qt.Key_Left) {
            Wallpapers.navigateBack();
            event.accepted = true;
        } else if (event.modifiers & Qt.AltModifier && event.key === Qt.Key_Right) {
            Wallpapers.navigateForward();
            event.accepted = true;
        } else if (event.key === Qt.Key_Left) {
            grid.moveSelection(-1);
            event.accepted = true;
        } else if (event.key === Qt.Key_Right) {
            grid.moveSelection(1);
            event.accepted = true;
        } else if (event.key === Qt.Key_Up) {
            grid.moveSelection(-grid.columns);
            event.accepted = true;
        } else if (event.key === Qt.Key_Down) {
            grid.moveSelection(grid.columns);
            event.accepted = true;
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            grid.activateCurrent();
            event.accepted = true;
        } else if (event.key === Qt.Key_Backspace) {
            if (filterField.text.length > 0) {
                filterField.text = filterField.text.substring(0, filterField.text.length - 1);
            }
            filterField.forceActiveFocus();
            event.accepted = true;
        } else if (event.modifiers & Qt.ControlModifier && event.key === Qt.Key_L) {
            addressBar.focusBreadcrumb();
            event.accepted = true;
        } else if (event.key === Qt.Key_Slash) {
            filterField.forceActiveFocus();
            event.accepted = true;
        } else {
            if (event.text.length > 0) {
                filterField.text += event.text;
                filterField.cursorPosition = filterField.text.length;
                filterField.forceActiveFocus();
            }
            event.accepted = true;
        }
    }

    implicitHeight: mainLayout.implicitHeight
    implicitWidth: mainLayout.implicitWidth

    StyledRectangularShadow {
        target: wallpaperGridBackground
        visible: !Appearance.inirEverywhere && !Appearance.zzzEverywhere
        opacity: wallpaperGridBackground.opacity
    }
    GlassBackground {
        id: wallpaperGridBackground
        anchors {
            fill: parent
            margins: Appearance.sizes.elevationMargin
        }
        focus: true
        Keys.forwardTo: [root]

        // Peek mode: get the panel out of the way so the desktop underneath is
        // readable. Kept slightly visible so it's obvious the picker is still up.
        opacity: root.peeking ? 0.12 : 1.0
        Behavior on opacity {
            enabled: Appearance.animationsEnabled
            NumberAnimation {
                duration: root.peeking ? Appearance.animation.menuExit.duration : Appearance.animation.menuEnter.duration
                easing.type: root.peeking ? Appearance.animation.menuExit.type : Appearance.animation.menuEnter.type
            }
        }
        border.width: (Appearance.inirEverywhere || Appearance.auroraEverywhere) ? 1 : 1
        border.color: Appearance.zzzEverywhere ? Appearance.zzz.hairlineStrong
            : Appearance.angelEverywhere ? Appearance.angel.colCardBorder
            : Appearance.inirEverywhere ? Appearance.inir.colBorder 
            : Appearance.auroraEverywhere ? Appearance.aurora.colTooltipBorder : Appearance.colors.colLayer0Border
        Behavior on border.color {
            enabled: Appearance.animationsEnabled
            ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
        }
        fallbackColor: Appearance.zzzEverywhere ? Appearance.zzz.paper : Appearance.colors.colLayer0
        inirColor: Appearance.inir.colLayer0
        auroraTransparency: Appearance.aurora.overlayTransparentize
        radius: Appearance.zzzEverywhere ? Appearance.zzz.panelRadius
            : Appearance.angelEverywhere ? Appearance.angel.roundingLarge
            : Appearance.inirEverywhere ? Appearance.inir.roundingLarge 
            : (Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 1)
        Behavior on radius { enabled: Appearance.animationsEnabled; NumberAnimation { duration: Appearance.animation.elementResize.duration; easing.type: Appearance.animation.elementResize.type; easing.bezierCurve: Appearance.animation.elementResize.bezierCurve } }

        property int calculatedRows: Math.ceil(grid.count / grid.columns)

        implicitWidth: gridColumnLayout.implicitWidth
        implicitHeight: gridColumnLayout.implicitHeight

        ZzzPanelBackdrop {
            anchors.fill: parent
            label: "WALLPAPER"
            index: "BROWSE"
            accentColor: Appearance.zzz.secondary
            ghostText: "WALL"
            showTicks: false
            showBurst: false
            showGrid: false
            horizontalBias: 0.16
            verticalBias: 0.01
            ghostStrength: 0.7
        }

        RowLayout {
            id: mainLayout
            anchors.fill: parent
            spacing: -4

            Rectangle {
                Layout.fillHeight: true
                Layout.margins: 4
                implicitWidth: quickDirColumnLayout.implicitWidth
                implicitHeight: quickDirColumnLayout.implicitHeight
                color: Appearance.zzzEverywhere ? Appearance.zzz.paperAlt
                    : Appearance.angelEverywhere ? Appearance.angel.colGlassCard
                    : Appearance.inirEverywhere ? Appearance.inir.colLayer1
                    : Appearance.auroraEverywhere ? Appearance.aurora.colSubSurface : Appearance.colors.colLayer1
                radius: Appearance.zzzEverywhere ? Appearance.zzz.controlRadius : wallpaperGridBackground.radius - Layout.margins
                border.width: Appearance.zzzEverywhere ? 1 : 0
                border.color: Appearance.zzzEverywhere ? Appearance.zzz.hairline : "transparent"
                Behavior on radius { enabled: Appearance.animationsEnabled; NumberAnimation { duration: Appearance.animation.elementResize.duration; easing.type: Appearance.animation.elementResize.type; easing.bezierCurve: Appearance.animation.elementResize.bezierCurve } }
                Behavior on color { enabled: Appearance.animationsEnabled; ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
                Behavior on border.width { enabled: Appearance.animationsEnabled; NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
                Behavior on border.color { enabled: Appearance.animationsEnabled; ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }

                ColumnLayout {
                    id: quickDirColumnLayout
                    anchors.fill: parent
                    spacing: 0

                    StyledText {
                        Layout.margins: 12
                        font.family: Appearance.zzzEverywhere ? Appearance.font.family.title : Appearance.font.family.main
                        font.pixelSize: Appearance.zzzEverywhere ? Appearance.font.pixelSize.large : Appearance.font.pixelSize.normal
                        font.weight: Appearance.zzzEverywhere ? Font.Black : Font.Medium
                        font.italic: Appearance.zzzEverywhere
                        text: Translation.tr("Pick a wallpaper")
                        color: Appearance.zzzEverywhere ? Appearance.zzz.ink : Appearance.colors.colOnLayer1
                        Behavior on color {
                            enabled: Appearance.animationsEnabled
                            ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
                        }
                    }
                    ListView {
                        // Quick dirs
                        Layout.fillHeight: true
                        Layout.margins: 4
                        implicitWidth: 140
                        clip: true
                        model: [
                            { icon: "home", name: "Home", path: Directories.home }, 
                            { icon: "docs", name: "Documents", path: Directories.documents }, 
                            { icon: "download", name: "Downloads", path: Directories.downloads }, 
                            { icon: "image", name: "Pictures", path: Directories.pictures }, 
                            { icon: "movie", name: "Videos", path: Directories.videos }, 
                            { icon: "", name: "---", path: "INTENTIONALLY_INVALID_DIR" }, 
                            { icon: "wallpaper", name: "Wallpapers", path: `${Directories.pictures}/Wallpapers` }, 
                            ...((Config.options?.policies?.weeb ?? 0) === 1 ? [{ icon: "favorite", name: "Homework", path: `${Directories.pictures}/homework` }] : []),
                        ]
                        delegate: RippleButton {
                            id: quickDirButton
                            required property var modelData
                            anchors {
                                left: parent.left
                                right: parent.right
                            }
                            onClicked: Wallpapers.setDirectory(quickDirButton.modelData.path)
                            enabled: modelData.icon.length > 0
                            toggled: Wallpapers.directory === Qt.resolvedUrl(modelData.path)
                            colBackgroundToggled: Appearance.zzzEverywhere ? Appearance.zzz.sticker : Appearance.colors.colSecondaryContainer
                            colBackgroundToggledHover: Appearance.zzzEverywhere ? ColorUtils.applyAlpha(Appearance.zzz.sticker, 0.88) : Appearance.colors.colSecondaryContainerHover
                            colRippleToggled: Appearance.zzzEverywhere ? ColorUtils.applyAlpha(Appearance.zzz.accent, 0.30) : Appearance.colors.colSecondaryContainerActive
                            buttonRadius: Appearance.zzzEverywhere ? Appearance.zzz.controlRadius : height / 2
                            implicitHeight: 38

                            contentItem: RowLayout {
                                MaterialSymbol {
                                    color: quickDirButton.toggled
                                        ? (Appearance.zzzEverywhere ? Appearance.zzz.onSticker : Appearance.colors.colOnSecondaryContainer)
                                        : (Appearance.zzzEverywhere ? Appearance.zzz.ink : Appearance.colors.colOnLayer1)
                                    iconSize: Appearance.font.pixelSize.larger
                                    text: quickDirButton.modelData.icon
                                    fill: quickDirButton.toggled ? 1 : 0
                                    animateFill: true
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignLeft
                                    color: quickDirButton.toggled
                                        ? (Appearance.zzzEverywhere ? Appearance.zzz.onSticker : Appearance.colors.colOnSecondaryContainer)
                                        : (Appearance.zzzEverywhere ? Appearance.zzz.ink : Appearance.colors.colOnLayer1)
                                    text: quickDirButton.modelData.name
                                }
                            }
                        }
                    }
                }
            }

            ColumnLayout {
                id: gridColumnLayout
                Layout.fillWidth: true
                Layout.fillHeight: true

                AddressBar {
                    id: addressBar
                    Layout.margins: 4
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    directory: Wallpapers.effectiveDirectory
                    onNavigateToDirectory: path => {
                        Wallpapers.setDirectory(path.length == 0 ? "/" : path);
                    }
                    radius: wallpaperGridBackground.radius - Layout.margins
                }

                // Multi-monitor indicator
                Rectangle {
                    visible: Config.options?.background?.multiMonitor?.enable ?? false
                    Layout.fillWidth: true
                    Layout.margins: 4
                    Layout.topMargin: 0
                    implicitHeight: visible ? monitorIndicatorText.implicitHeight + 16 : 0
                    color: Appearance.zzzEverywhere ? Appearance.zzz.paperAlt
                        : Appearance.inirEverywhere ? Appearance.inir.colLayer1
                        : Appearance.auroraEverywhere ? Appearance.aurora.colSubSurface
                        : Appearance.colors.colLayer1
                    radius: Appearance.zzzEverywhere ? Appearance.zzz.controlRadius : wallpaperGridBackground.radius - Layout.margins
                    border.width: Appearance.zzzEverywhere ? 1 : Appearance.inirEverywhere ? 1 : 0
                    border.color: Appearance.zzzEverywhere ? Appearance.zzz.hairline : Appearance.inirEverywhere ? Appearance.inir.colBorder : "transparent"
                    Behavior on radius { enabled: Appearance.animationsEnabled; NumberAnimation { duration: Appearance.animation.elementResize.duration; easing.type: Appearance.animation.elementResize.type; easing.bezierCurve: Appearance.animation.elementResize.bezierCurve } }
                    Behavior on color { enabled: Appearance.animationsEnabled; ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
                    Behavior on border.width { enabled: Appearance.animationsEnabled; NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
                    Behavior on border.color { enabled: Appearance.animationsEnabled; ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: Appearance.sizes.spacingSmall
                        spacing: Appearance.sizes.spacingSmall

                        MaterialSymbol {
                            text: "monitor"
                            font.pixelSize: Appearance.font.pixelSize.normal
                            color: Appearance.zzzEverywhere ? Appearance.zzz.accent : Appearance.colors.colPrimary
                            Behavior on color {
                                enabled: Appearance.animationsEnabled
                                ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
                            }
                        }

                        StyledText {
                            id: monitorIndicatorText
                            Layout.fillWidth: true
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.Medium
                            text: root.selectedMonitor ?
                                Translation.tr("Configuring monitor: %1").arg(root.selectedMonitor) :
                                Translation.tr("Multi-monitor mode active")
                            color: Appearance.zzzEverywhere ? Appearance.zzz.ink : Appearance.colors.colPrimary
                            Behavior on color {
                                enabled: Appearance.animationsEnabled
                                ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
                            }
                        }
                    }
                }

                Item {
                    id: gridDisplayRegion
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    StyledIndeterminateProgressBar {
                        id: indeterminateProgressBar
                        visible: Wallpapers.thumbnailGenerationRunning && value == 0
                        anchors {
                            bottom: parent.top
                            left: parent.left
                            right: parent.right
                            leftMargin: 4
                            rightMargin: 4
                        }
                    }

                    StyledProgressBar {
                        visible: Wallpapers.thumbnailGenerationRunning && value > 0
                        value: Wallpapers.thumbnailGenerationProgress
                        anchors.fill: indeterminateProgressBar
                    }

                    GridView {
                        id: grid
                        visible: Wallpapers.folderModel.count > 0

                        readonly property int columns: root.columns
                        readonly property int rows: Math.max(1, Math.ceil(count / columns))
                        property int currentIndex: 0

                        anchors.fill: parent
                        cellWidth: width / root.columns
                        cellHeight: cellWidth / root.previewCellAspectRatio
                        interactive: true
                        clip: true
                        keyNavigationWraps: true
                        boundsBehavior: Flickable.StopAtBounds
                        bottomMargin: extraOptions.implicitHeight
                        ScrollBar.vertical: StyledScrollBar {}

                        Component.onCompleted: {
                            root.updateThumbnails()
                        }

                        function moveSelection(delta) {
                            if (!grid.model || grid.model.count <= 0)
                                return
                            currentIndex = Math.max(0, Math.min(grid.model.count - 1, currentIndex + delta));
                            positionViewAtIndex(currentIndex, GridView.Contain);
                        }

                        function activateCurrent() {
                            if (!grid.model || grid.model.count <= 0)
                                return
                            const filePath = grid.model.get(currentIndex, "filePath")
                            const isDir = grid.model.get(currentIndex, "fileIsDir")
                            if (isDir) {
                                Wallpapers.setDirectory(filePath);
                            } else {
                                root.selectWallpaperPath(filePath);
                            }
                        }

                        model: Wallpapers.folderModelReady ? Wallpapers.folderModel : null
                        onModelChanged: currentIndex = 0
                        onCountChanged: currentIndex = count > 0 ? Math.min(currentIndex, count - 1) : 0
                        onCurrentIndexChanged: root.syncHighlight()
                        delegate: WallpaperDirectoryItem {
                            required property int index
                            required property string filePath
                            required property string fileName
                            required property bool fileIsDir
                            required property url fileUrl

                            // Compute once; avoids two separate Wallpapers.isCurrentWallpaperPath
                            // calls per binding re-evaluation (colBackground + colText).
                            readonly property bool _isCurrent: Wallpapers.isCurrentWallpaperPath(filePath, root.currentSelectionTarget, root.selectedMonitor)

                            fileModelData: ({
                                filePath: filePath,
                                fileName: fileName,
                                fileIsDir: fileIsDir,
                                fileUrl: fileUrl
                            })
                            width: grid.cellWidth
                            height: grid.cellHeight
                            isCurrent: _isCurrent
                            staggerIndex: index
                            cascade: root.cascadeActive
                            colBackground: (index === grid?.currentIndex || containsMouse) ? Appearance.colors.colPrimary : _isCurrent ? Appearance.colors.colSecondaryContainer : ColorUtils.transparentize(Appearance.colors.colPrimaryContainer)
                            colText: (index === grid.currentIndex || containsMouse) ? Appearance.colors.colOnPrimary : _isCurrent ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer0

                            onEntered: {
                                grid.currentIndex = index;
                            }

                            onActivated: {
                                if (fileIsDir) {
                                    Wallpapers.setDirectory(filePath);
                                } else {
                                    root.selectWallpaperPath(filePath);
                                }
                            }
                        }

                        // Traveling selection ring.
                        //
                        // Each edge is animated independently: the edge leading the
                        // move arrives first and the trailing edge lags, so the ring
                        // stretches toward its destination instead of sliding rigidly.
                        // Lives inside contentItem so it scrolls with the cells.
                        Rectangle {
                            id: selectionRing
                            parent: grid.contentItem
                            z: 2

                            readonly property real inset: Appearance.sizes.wallpaperSelectorItemMargins

                            property bool goingRight: true
                            property bool goingDown: true
                            // Set for one frame to teleport instead of sweeping (folder jumps).
                            property bool snapping: true
                            property int prevIndex: -1

                            // Edge positions are assigned, never bound, so the direction
                            // flags are always settled before the Behaviors read them.
                            property real animL: 0
                            property real animT: 0
                            property real animR: 0
                            property real animB: 0

                            function retarget(): void {
                                const cols = Math.max(1, grid.columns);
                                const index = Math.max(0, grid.currentIndex);
                                const prev = selectionRing.prevIndex < 0 ? index : selectionRing.prevIndex;
                                selectionRing.goingRight = (index % cols) >= (prev % cols);
                                selectionRing.goingDown = Math.floor(index / cols) >= Math.floor(prev / cols);
                                selectionRing.prevIndex = index;

                                const left = (index % cols) * grid.cellWidth + selectionRing.inset;
                                const top = Math.floor(index / cols) * grid.cellHeight + selectionRing.inset;
                                selectionRing.animL = left;
                                selectionRing.animT = top;
                                selectionRing.animR = left + grid.cellWidth - selectionRing.inset * 2;
                                selectionRing.animB = top + grid.cellHeight - selectionRing.inset * 2;
                            }

                            function snapNext(): void {
                                selectionRing.snapping = true;
                                selectionRing.prevIndex = -1;
                                selectionRing.retarget();
                                Qt.callLater(() => selectionRing.snapping = false);
                            }

                            Connections {
                                target: grid
                                function onCurrentIndexChanged() { selectionRing.retarget() }
                                function onCellWidthChanged() { selectionRing.snapNext() }
                                function onCellHeightChanged() { selectionRing.snapNext() }
                            }

                            readonly property int fastMs: selectionRing.snapping ? 0 : Appearance.animation.travel.duration
                            readonly property int slowMs: selectionRing.snapping ? 0 : Math.round(Appearance.animation.travel.duration * 1.6)

                            Behavior on animL {
                                enabled: Appearance.animationsEnabled
                                NumberAnimation { duration: selectionRing.goingRight ? selectionRing.slowMs : selectionRing.fastMs; easing.type: Appearance.animation.travel.type }
                            }
                            Behavior on animR {
                                enabled: Appearance.animationsEnabled
                                NumberAnimation { duration: selectionRing.goingRight ? selectionRing.fastMs : selectionRing.slowMs; easing.type: Appearance.animation.travel.type }
                            }
                            Behavior on animT {
                                enabled: Appearance.animationsEnabled
                                NumberAnimation { duration: selectionRing.goingDown ? selectionRing.slowMs : selectionRing.fastMs; easing.type: Appearance.animation.travel.type }
                            }
                            Behavior on animB {
                                enabled: Appearance.animationsEnabled
                                NumberAnimation { duration: selectionRing.goingDown ? selectionRing.fastMs : selectionRing.slowMs; easing.type: Appearance.animation.travel.type }
                            }

                            x: selectionRing.animL
                            y: selectionRing.animT
                            width: Math.max(0, selectionRing.animR - selectionRing.animL)
                            height: Math.max(0, selectionRing.animB - selectionRing.animT)

                            visible: grid.visible && grid.count > 0 && grid.currentIndex >= 0
                            color: "transparent"
                            radius: Appearance.rounding.normal
                            border.width: 2
                            border.color: Appearance.colors.colPrimary

                            Component.onCompleted: selectionRing.snapNext()
                        }

                        layer.enabled: true
                        layer.effect: GE.OpacityMask {
                            maskSource: Rectangle {
                                width: gridDisplayRegion.width
                                height: gridDisplayRegion.height
                                radius: wallpaperGridBackground.radius
                            }
                        }
                    }

                    Toolbar {
                        id: extraOptions
                        anchors {
                            bottom: parent.bottom
                            horizontalCenter: parent.horizontalCenter
                            bottomMargin: 8
                        }
                        
                        // Calculate screen position for aurora blur
                        screenX: {
                            const mapped = extraOptions.mapToGlobal(0, 0)
                            return mapped.x
                        }
                        screenY: {
                            const mapped = extraOptions.mapToGlobal(0, 0)
                            return mapped.y
                        }

                        IconToolbarButton {
                            implicitWidth: height
                            onClicked: root.openWallpaperLauncher("")
                            altAction: () => root.openWallpaperLauncher("animated")
                            text: "wallpaper_slideshow"
                            StyledToolTip {
                                text: Translation.tr("Open wallpaper carousel\nRight-click for animated wallpapers")
                            }
                        }

                        IconToolbarButton {
                            implicitWidth: height
                            onClicked: {
                                Wallpapers.openFallbackPicker(root.useDarkMode);
                                GlobalStates.wallpaperSelectorOpen = false;
                            }
                            altAction: () => {
                                Wallpapers.openFallbackPicker(root.useDarkMode);
                                GlobalStates.wallpaperSelectorOpen = false;
                                Config.setNestedValue("wallpaperSelector.useSystemFileDialog", true)
                            }
                            text: "open_in_new"
                            StyledToolTip {
                                text: Translation.tr("Use the system file picker instead\nRight-click to make this the default behavior")
                            }
                        }

                        IconToolbarButton {
                            implicitWidth: height
                            onClicked: {
                                Wallpapers.randomFromCurrentFolder(root.useDarkMode);
                            }
                            text: "ifl"
                            StyledToolTip {
                                text: Translation.tr("Pick random from this folder")
                            }
                        }

                        IconToolbarButton {
                            implicitWidth: height
                            onClicked: {
                                root.useDarkMode = !root.useDarkMode
                                MaterialThemeLoader.setDarkMode(root.useDarkMode)
                            }
                            text: root.useDarkMode ? "dark_mode" : "light_mode"
                            StyledToolTip {
                                text: Translation.tr("Click to toggle light/dark mode\n(applied when wallpaper is chosen)")
                            }
                        }

                        ToolbarTextField {
                            id: filterField
                            placeholderText: focus ? Translation.tr("Search wallpapers") : Translation.tr("Hit \"/\" to search")

                            // Style
                            clip: true
                            font.pixelSize: Appearance.font.pixelSize.small

                            // Search
                            onTextChanged: {
                                Wallpapers.searchQuery = text;
                            }

                            Keys.onPressed: event => {
                                if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_V) { // Intercept Ctrl+V to handle "paste to go to" in pickers
                                    root.handleFilePasting(event);
                                    return;
                                }
                                // The search field holds focus while browsing, so the
                                // peek/live shortcuts have to be caught here too.
                                else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_Space) {
                                    root.peeking = !root.peeking;
                                    event.accepted = true;
                                    return;
                                }
                                else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_P) {
                                    root.toggleLivePreview();
                                    event.accepted = true;
                                    return;
                                }
                                else if (text.length !== 0) {
                                    // No filtering, just navigate grid
                                    if (event.key === Qt.Key_Down) {
                                        grid.moveSelection(grid.columns);
                                        event.accepted = true;
                                        return;
                                    }
                                    if (event.key === Qt.Key_Up) {
                                        grid.moveSelection(-grid.columns);
                                        event.accepted = true;
                                        return;
                                    }
                                }
                                event.accepted = false;
                            }
                        }

                        IconToolbarButton {
                            implicitWidth: height
                            toggled: root.peeking
                            onClicked: root.peeking = !root.peeking
                            text: root.peeking ? "visibility_off" : "visibility"
                            StyledToolTip {
                                text: Translation.tr("Peek at the desktop (Ctrl+Space)\nFades the picker so you can see the wallpaper behind it")
                            }
                        }

                        IconToolbarButton {
                            implicitWidth: height
                            toggled: root.previewPaneVisible
                            onClicked: Config.setNestedValue("wallpaperSelector.showPreviewPane", !root.previewPaneVisible)
                            text: "splitscreen_right"
                            StyledToolTip {
                                text: Translation.tr("Toggle the large preview")
                            }
                        }

                        IconToolbarButton {
                            implicitWidth: height
                            onClicked: {
                                GlobalStates.wallpaperSelectorOpen = false
                                Config.setNestedValue("wallpaperSelector.style", "coverflow")
                                GlobalStates.coverflowSelectorOpen = true
                            }
                            text: "view_carousel"
                            StyledToolTip {
                                text: Translation.tr("Switch to coverflow view")
                            }
                        }

                        IconToolbarButton {
                            implicitWidth: height
                            onClicked: {
                                GlobalStates.wallpaperSelectorOpen = false;
                            }
                            text: "close"
                            StyledToolTip {
                                text: Translation.tr("Cancel wallpaper selection")
                            }
                        }
                    }
                }
            }

            // Hero preview. Width animates so toggling it feels like the panel
            // reflows rather than the pane blinking in and out.
            WallpaperPreviewPane {
                id: previewPane
                Layout.fillHeight: true
                Layout.margins: 4
                Layout.leftMargin: 0
                Layout.preferredWidth: root.previewPaneVisible ? 400 : 0
                visible: Layout.preferredWidth > 1
                clip: true

                // Bound to _highlight directly, not the split convenience properties,
                // so path and isDir are always read from the same consistent snapshot.
                sourcePath: root._highlight.isDir ? "" : root._highlight.path
                isDirectory: root._highlight.isDir
                livePreviewActive: root.livePreviewEnabled
                targetMonitor: root.selectedMonitor
                selectionTarget: root.currentSelectionTarget
                isApplied: !root._highlight.isDir && root._highlight.path.length > 0 && Wallpapers.isCurrentWallpaperPath(root._highlight.path, root.currentSelectionTarget, root.selectedMonitor)

                onApplyRequested: root.selectWallpaperPath(root.highlightPath)
                onLivePreviewToggled: root.toggleLivePreview()

                Behavior on Layout.preferredWidth {
                    enabled: Appearance.animationsEnabled
                    NumberAnimation {
                        duration: Appearance.animation.elementResize.duration
                        easing.type: Appearance.animation.elementResize.type
                        easing.bezierCurve: Appearance.animation.elementResize.bezierCurve
                    }
                }
            }
        }
    }

    Connections {
        target: GlobalStates
        function onWallpaperSelectorOpenChanged() {
            if (GlobalStates.wallpaperSelectorOpen) {
                Wallpapers.searchQuery = ""
                root._originalPreviewSource = Config.options?.appearance?.wallpaperTheming?.previewSourcePath ?? ""
                root.peeking = false
                Qt.callLater(() => {
                    root.syncDirectoryToCurrentSelection()
                    root.updateThumbnails()
                    root.syncHighlight()
                    root.startCascade()
                })
                if (monitorIsFocused) {
                    filterField.forceActiveFocus();
                }
            } else {
                // Closed without committing — put the palette back.
                livePreviewTimer.stop()
                root.peeking = false
                root.revertLivePreview()
            }
        }
    }

    Connections {
        target: Wallpapers
        function onChanged() {
            GlobalStates.wallpaperSelectorOpen = false;
        }
    }
}
