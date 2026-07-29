pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import Qt5Compat.GraphicalEffects as GE

/**
 * Large hero preview beside the wallpaper grid.
 *
 * Shows whatever the grid is currently highlighting, cross-fading between
 * wallpapers so browsing reads as one continuous surface rather than a
 * sequence of pops. Metadata (resolution / file size) is resolved lazily by a
 * single debounced `identify` per distinct file and memoised for the session.
 */
Rectangle {
    id: root

    // What to show. Empty string renders the placeholder.
    property string sourcePath: ""
    property bool isDirectory: false
    // The highlighted wallpaper is the one already in use for this target.
    property bool isApplied: false
    // Live theming is following the highlight.
    property bool livePreviewActive: false
    property string targetMonitor: ""
    property string selectionTarget: "main"

    signal applyRequested
    signal livePreviewToggled

    readonly property bool hasSelection: !root.isDirectory && root.sourcePath.length > 0
    readonly property string fileName: {
        if (!root.hasSelection)
            return ""
        const parts = root.sourcePath.split("/");
        return parts[parts.length - 1] ?? "";
    }
    readonly property string extensionLabel: {
        const dot = root.fileName.lastIndexOf(".");
        return dot >= 0 ? root.fileName.slice(dot + 1).toUpperCase() : "";
    }
    readonly property bool isVideo: root.hasSelection && Images.isValidVideoByName(root.fileName)

    color: Appearance.angelEverywhere ? Appearance.angel.colGlassCard : Appearance.inirEverywhere ? Appearance.inir.colLayer1 : Appearance.auroraEverywhere ? Appearance.aurora.colSubSurface : Appearance.colors.colLayer1
    radius: Appearance.rounding.normal
    border.width: Appearance.inirEverywhere ? 1 : 0
    border.color: Appearance.inirEverywhere ? Appearance.inir.colBorder : "transparent"

    // ------------------------------------------------------------------
    // Hero cross-fade
    //
    // Two layers ping-pong: the incoming wallpaper is decoded into the back
    // layer and only swapped to the front once it reports Ready, so there is
    // never a flash of empty card between two wallpapers.
    // ------------------------------------------------------------------
    property string _pathA: ""
    property string _pathB: ""
    property bool _showA: true
    // The source the back layer is currently racing to decode. Cached rather than
    // recomputed in the status handlers so video paths don't re-trigger first-frame
    // extraction on every status change.
    property string _wantedSource: ""

    function _heroSource(path: string): string {
        const clean = FileUtils.trimFileProtocol(String(path ?? ""));
        if (clean.length === 0)
            return "";
        if (Images.isValidVideoByName(clean)) {
            // Videos can't be decoded by Image — fall back to the cached first frame.
            const frame = Wallpapers.videoFirstFrames[clean];
            if (frame)
                return frame.startsWith("file://") ? frame : "file://" + frame;
            Wallpapers.ensureVideoFirstFrame(clean);
            const thumb = Wallpapers.getExpectedThumbnailPath(clean, "x-large");
            return thumb.length > 0 ? "file://" + thumb : "";
        }
        return "file://" + clean;
    }

    onSourcePathChanged: root._present()
    onIsDirectoryChanged: root._present()

    function _present(): void {
        // Derived from sourcePath directly, never from `hasSelection` — that is a
        // binding, and its re-evaluation is not ordered against this change handler,
        // so reading it here saw a stale `false` and blanked the hero on first show.
        const raw = FileUtils.trimFileProtocol(String(root.sourcePath ?? ""));
        const next = raw.length === 0 ? "" : root._heroSource(raw);
        root._wantedSource = next;
        const front = root._showA ? root._pathA : root._pathB;
        if (next === front)
            return;
        if (next.length === 0) {
            // Nothing to show — fade the front layer out rather than swapping.
            if (root._showA)
                root._pathA = "";
            else
                root._pathB = "";
            return;
        }
        if (root._showA)
            root._pathB = next;
        else
            root._pathA = next;
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Appearance.sizes.spacingSmall
        spacing: Appearance.sizes.spacingSmall

        Item {
            id: heroArea
            Layout.fillWidth: true
            Layout.fillHeight: true

            readonly property real _dpr: root.window ? root.window.devicePixelRatio : 1

            layer.enabled: Appearance.effectsEnabled
            layer.effect: GE.OpacityMask {
                maskSource: Rectangle {
                    width: heroArea.width
                    height: heroArea.height
                    radius: Appearance.rounding.small
                }
            }

            Rectangle {
                anchors.fill: parent
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer2
            }

            HeroLayer {
                id: layerA
                source: root._pathA
                sourceSize.width: Math.round(heroArea.width * heroArea._dpr)
                sourceSize.height: Math.round(heroArea.height * heroArea._dpr)
                opacity: (root._showA && root._pathA.length > 0) ? 1 : 0
                scale: root._showA ? 1.0 : 1.06
                onStatusChanged: {
                    if (status === Image.Ready && !root._showA && root._pathA === root._wantedSource)
                        root._showA = true;
                }
            }

            HeroLayer {
                id: layerB
                source: root._pathB
                sourceSize.width: Math.round(heroArea.width * heroArea._dpr)
                sourceSize.height: Math.round(heroArea.height * heroArea._dpr)
                opacity: (!root._showA && root._pathB.length > 0) ? 1 : 0
                scale: !root._showA ? 1.0 : 1.06
                onStatusChanged: {
                    if (status === Image.Ready && root._showA && root._pathB === root._wantedSource)
                        root._showA = false;
                }
            }

            // Bottom scrim so the chips stay legible over bright wallpapers.
            Rectangle {
                anchors {
                    left: parent.left
                    right: parent.right
                    bottom: parent.bottom
                }
                height: Math.min(parent.height * 0.45, 120)
                opacity: root.hasSelection ? 1 : 0
                gradient: Gradient {
                    GradientStop {
                        position: 0.0
                        color: "transparent"
                    }
                    GradientStop {
                        position: 1.0
                        color: ColorUtils.transparentize(Appearance.m3colors.m3scrim, 0.35)
                    }
                }
                Behavior on opacity {
                    enabled: Appearance.animationsEnabled
                    NumberAnimation {
                        duration: Appearance.animation.menuEnter.duration
                        easing.type: Appearance.animation.menuEnter.type
                    }
                }
            }

            // Placeholder while hovering a folder or before anything is highlighted.
            ColumnLayout {
                anchors.centerIn: parent
                spacing: Appearance.sizes.spacingSmall
                opacity: root.hasSelection ? 0 : 1
                visible: opacity > 0
                Behavior on opacity {
                    enabled: Appearance.animationsEnabled
                    NumberAnimation {
                        duration: Appearance.animation.menuEnter.duration
                        easing.type: Appearance.animation.menuEnter.type
                    }
                }

                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.isDirectory ? "folder_open" : "wallpaper"
                    iconSize: 44
                    color: Appearance.colors.colOnLayer2
                    opacity: 0.5
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.isDirectory ? Translation.tr("Open to browse") : Translation.tr("Highlight a wallpaper")
                    color: Appearance.colors.colOnLayer2
                    opacity: 0.7
                    font.pixelSize: Appearance.font.pixelSize.small
                }
            }

            // Status chips, top-right.
            RowLayout {
                anchors {
                    top: parent.top
                    right: parent.right
                    margins: Appearance.sizes.spacingSmall
                }
                spacing: 6

                PreviewChip {
                    icon: "bolt"
                    label: Translation.tr("Live")
                    shown: root.livePreviewActive
                    accent: true
                }
                PreviewChip {
                    icon: "check_circle"
                    label: root.targetMonitor.length > 0 ? Translation.tr("On %1").arg(root.targetMonitor) : Translation.tr("Applied")
                    shown: root.isApplied
                    accent: true
                }
            }
        }

        // ------------------------------------------------------------------
        // Metadata + actions
        // ------------------------------------------------------------------
        StyledText {
            Layout.fillWidth: true
            Layout.leftMargin: 4
            Layout.rightMargin: 4
            text: root.hasSelection ? root.fileName : " "
            elide: Text.ElideMiddle
            maximumLineCount: 1
            font.pixelSize: Appearance.font.pixelSize.normal
            font.weight: Font.DemiBold
            color: Appearance.colors.colOnLayer1
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 4
            Layout.rightMargin: 4
            spacing: 6

            PreviewChip {
                icon: root.isVideo ? "movie" : "image"
                label: root.extensionLabel
                shown: root.extensionLabel.length > 0
            }
            PreviewChip {
                icon: "aspect_ratio"
                label: metadata.dimensions
                shown: metadata.dimensions.length > 0
            }
            PreviewChip {
                icon: "hard_drive"
                label: metadata.fileSize
                shown: metadata.fileSize.length > 0
            }
            Item {
                Layout.fillWidth: true
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            RippleButtonWithIcon {
                Layout.fillWidth: true
                implicitHeight: 40
                enabled: root.hasSelection
                opacity: enabled ? 1 : 0.45
                materialIcon: "wallpaper"
                mainText: root.isApplied ? Translation.tr("Applied") : Translation.tr("Set wallpaper")
                buttonRadius: Appearance.rounding.small
                colBackground: root.isApplied ? Appearance.colors.colSecondaryContainer : Appearance.colors.colPrimary
                colBackgroundHover: root.isApplied ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colPrimaryHover
                colRipple: root.isApplied ? Appearance.colors.colSecondaryContainerActive : Appearance.colors.colPrimaryActive
                mainContentComponent: Component {
                    StyledText {
                        text: root.isApplied ? Translation.tr("Applied") : Translation.tr("Set wallpaper")
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.Medium
                        color: root.isApplied ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnPrimary
                    }
                }
                onClicked: root.applyRequested()
            }

            RippleButton {
                implicitWidth: 40
                implicitHeight: 40
                buttonRadius: Appearance.rounding.small
                toggled: root.livePreviewActive
                colBackground: Appearance.colors.colLayer2
                colBackgroundHover: Appearance.colors.colLayer2Hover
                colBackgroundToggled: Appearance.colors.colSecondaryContainer
                colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
                colRippleToggled: Appearance.colors.colSecondaryContainerActive
                onClicked: root.livePreviewToggled()

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "bolt"
                    iconSize: Appearance.font.pixelSize.larger
                    fill: root.livePreviewActive ? 1 : 0
                    animateFill: true
                    color: root.livePreviewActive ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2
                }

                StyledToolTip {
                    text: Translation.tr("Live theme preview\nRecolors the shell from whatever you highlight")
                }
            }
        }
    }

    // ------------------------------------------------------------------
    // Lazy metadata resolution
    // ------------------------------------------------------------------
    QtObject {
        id: metadata
        property string dimensions: ""
        property string fileSize: ""
    }

    // Memoised per path so re-visiting a wallpaper never respawns a process.
    property var _metaCache: ({})
    property string _metaPending: ""

    function _friendlySize(bytes: int): string {
        if (bytes <= 0)
            return "";
        const units = ["B", "KB", "MB", "GB"];
        let value = bytes;
        let unit = 0;
        while (value >= 1024 && unit < units.length - 1) {
            value /= 1024;
            unit++;
        }
        return `${value < 10 && unit > 0 ? value.toFixed(1) : Math.round(value)} ${units[unit]}`;
    }

    function _applyMeta(path: string): bool {
        const cached = root._metaCache[path];
        if (cached === undefined)
            return false;
        metadata.dimensions = cached.dimensions;
        metadata.fileSize = cached.fileSize;
        return true;
    }

    onHasSelectionChanged: root._refreshMetadata()
    onFileNameChanged: root._refreshMetadata()

    function _refreshMetadata(): void {
        if (!root.hasSelection) {
            metadata.dimensions = "";
            metadata.fileSize = "";
            metaDebounce.stop();
            return;
        }
        const path = FileUtils.trimFileProtocol(String(root.sourcePath));
        if (root._applyMeta(path))
            return;
        metadata.dimensions = "";
        metadata.fileSize = "";
        metaDebounce.restart();
    }

    property Timer _metaDebounce: Timer {
        id: metaDebounce
        interval: 220
        onTriggered: {
            if (!root.hasSelection || metaProc.running)
                return;
            const path = FileUtils.trimFileProtocol(String(root.sourcePath));
            if (path.length === 0 || root._metaCache[path] !== undefined)
                return;
            root._metaPending = path;
            const quoted = "'" + StringUtils.shellSingleQuoteEscape(path) + "'";
            // `identify -ping` reads headers only, so this stays cheap. Videos have
            // no still header to read, so they report size only. Emits exactly two
            // lines ("W H" then bytes) and stays silent on failure.
            const probe = root.isVideo ? "printf '0 0'" : `identify -ping -format '%w %h' ${quoted}[0] 2>/dev/null || printf '0 0'`;
            metaProc.exec(["/usr/bin/bash", "-c", `${probe}; printf '\\n'; stat -c %s ${quoted} 2>/dev/null || printf '0'`]);
        }
    }

    property Process _metaProc: Process {
        id: metaProc
        stdout: StdioCollector {
            onStreamFinished: {
                const path = root._metaPending;
                root._metaPending = "";
                if (path.length === 0)
                    return;

                const lines = String(text ?? "").trim().split("\n");
                const dims = (lines[0] ?? "").trim().split(/\s+/);
                const w = parseInt(dims[0] ?? "0", 10);
                const h = parseInt(dims[1] ?? "0", 10);
                const bytes = parseInt((lines[1] ?? "0").trim(), 10);

                const entry = {
                    dimensions: (w > 0 && h > 0) ? `${w}×${h}` : "",
                    fileSize: root._friendlySize(bytes)
                };
                root._metaCache[path] = entry;
                // Only paint it if the highlight hasn't moved on since we asked.
                if (FileUtils.trimFileProtocol(String(root.sourcePath)) === path)
                    root._applyMeta(path);
            }
        }
    }

    // One half of the hero cross-fade. The front layer settles to 1.0 while the
    // back layer waits at a slight zoom, so promotion reads as the image easing
    // into place rather than a hard cut.
    component HeroLayer: Image {
        asynchronous: true
        cache: true
        retainWhileLoading: true
        fillMode: Image.PreserveAspectCrop
        mipmap: true
        anchors.fill: parent
        Behavior on opacity {
            enabled: Appearance.animationsEnabled
            NumberAnimation {
                duration: Appearance.animation.morphSwap.duration
                easing.type: Appearance.animation.morphSwap.type
            }
        }
        Behavior on scale {
            enabled: Appearance.animationsEnabled
            NumberAnimation {
                duration: 620
                easing.type: Easing.OutCubic
            }
        }
    }

    // Small pill used for the status/metadata chips.
    component PreviewChip: Rectangle {
        id: chip
        property string icon: ""
        property string label: ""
        property bool shown: true
        property bool accent: false

        visible: opacity > 0
        opacity: chip.shown ? 1 : 0
        clip: true
        implicitWidth: chipRow.implicitWidth + 16
        implicitHeight: 24
        // Collapse the width alongside the fade so neighbouring chips slide
        // over instead of snapping when one drops out.
        Layout.preferredWidth: chip.shown ? chip.implicitWidth : 0
        radius: Appearance.rounding.full
        color: chip.accent ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer2

        Behavior on opacity {
            enabled: Appearance.animationsEnabled
            NumberAnimation {
                duration: Appearance.animation.menuEnter.duration
                easing.type: Appearance.animation.menuEnter.type
            }
        }
        Behavior on Layout.preferredWidth {
            enabled: Appearance.animationsEnabled
            NumberAnimation {
                duration: Appearance.animation.elementResize.duration
                easing.type: Appearance.animation.elementResize.type
                easing.bezierCurve: Appearance.animation.elementResize.bezierCurve
            }
        }

        RowLayout {
            id: chipRow
            anchors.centerIn: parent
            spacing: 4

            MaterialSymbol {
                text: chip.icon
                iconSize: Appearance.font.pixelSize.small
                color: chip.accent ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2
            }
            StyledText {
                text: chip.label
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.Medium
                color: chip.accent ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2
            }
        }
    }
}
