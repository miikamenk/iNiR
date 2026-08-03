pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import QtQuick.Effects
import Qt5Compat.GraphicalEffects as GE

// System dashboard content — stat cards with history graphs for CPU, RAM,
// GPU, VRAM, network, disk, and temperatures. Rendered inside DashboardWindow.
Item {
    id: root

    // Injected by DashboardWindow when present (blur alignment)
    property var dashboardScreen: null
    readonly property real screenWidth: dashboardScreen?.width ?? Quickshell.screens[0]?.width ?? 1920
    readonly property real screenHeight: dashboardScreen?.height ?? Quickshell.screens[0]?.height ?? 1080

    implicitWidth: 880
    implicitHeight: contentColumn.implicitHeight + 2 * panelPadding

    readonly property int panelPadding: 20

    // Keep the service polling while the dashboard is open (paired on destroy)
    Component.onCompleted: ResourceUsage.keepAlive()
    Component.onDestruction: ResourceUsage.releaseKeepAlive()

    // ── Style tokens ──
    readonly property bool angelEverywhere: Appearance.angelEverywhere
    readonly property bool liquidEverywhere: Appearance.liquidEverywhere
    readonly property bool inirEverywhere: Appearance.inirEverywhere
    readonly property bool auroraEverywhere: Appearance.auroraEverywhere
    readonly property color colText: angelEverywhere ? Appearance.angel.colText
        : liquidEverywhere ? Appearance.liquid.colText
        : inirEverywhere ? Appearance.inir.colText : Appearance.colors.colOnLayer1
    readonly property color colSubtext: angelEverywhere ? Appearance.angel.colTextSecondary
        : liquidEverywhere ? Appearance.liquid.colTextSecondary
        : inirEverywhere ? Appearance.inir.colTextSecondary : Appearance.colors.colSubtext
    readonly property color colPrimary: Appearance.colors.colPrimary
    readonly property color colSecondary: Appearance.colors.colSecondary
    readonly property color colTertiary: Appearance.colors.colTertiary
    readonly property color colError: Appearance.m3colors.m3error
    readonly property color colCard: angelEverywhere ? Appearance.angel.colGlassCard
        : liquidEverywhere ? Appearance.liquid.colGlassCard
        : inirEverywhere ? Appearance.inir.colLayer1
        : auroraEverywhere ? Appearance.aurora.colSubSurface
        : Appearance.colors.colLayer1
    readonly property real cardRadius: angelEverywhere ? Appearance.angel.roundingNormal
        : liquidEverywhere ? Appearance.liquid.roundingNormal
        : inirEverywhere ? Appearance.inir.roundingNormal : Appearance.rounding.normal

    readonly property string wallpaperUrl: Wallpapers.effectiveWallpaperUrl
    readonly property bool realGlass: Appearance.liquidRealGlass
    readonly property bool useWallpaperBackdrop: auroraEverywhere && !inirEverywhere
        && !Appearance.gameModeMinimal && wallpaperUrl.length > 0 && !realGlass
    // The liquid shader's edge refraction needs the wallpaper texture even in
    // real-glass mode, where nothing is painted from it (same as GlassBackground).
    readonly property bool wantsRefractionTexture: liquidEverywhere
        && Appearance.liquid.shaderEnabled && Appearance.effectsEnabled
        && Appearance.liquid.shaderRefraction > 0 && wallpaperUrl.length > 0

    // Wallpaper-blended tint, same recipe as the bar/sidebars, so the panel
    // matches them instead of reading near-black raw colLayer0.
    ColorQuantizer {
        id: dashboardQuantizer
        source: (auroraEverywhere || angelEverywhere) ? root.wallpaperUrl : ""
        depth: 0
        rescaleSize: 10
    }
    readonly property color wallpaperDominantColor: dashboardQuantizer.colors?.[0] ?? Appearance.colors.colPrimary
    readonly property QtObject blendedColors: AdaptedMaterialScheme {
        color: ColorUtils.mix(root.wallpaperDominantColor, Appearance.colors.colPrimaryContainer, 0.8)
            || Appearance.m3colors.m3secondaryContainer
    }

    // ═══ Background ═══
    StyledRectangularShadow {
        target: background
        visible: !root.inirEverywhere && !Appearance.gameModeMinimal
    }
    Rectangle {
        id: background
        anchors.fill: parent
        color: root.inirEverywhere ? Appearance.inir.colLayer0
            : root.auroraEverywhere ? ColorUtils.applyAlpha(root.blendedColors?.colLayer0 ?? Appearance.colors.colLayer0, Appearance.panelSurfaceAlpha)
            : Appearance.colors.colLayer0
        radius: root.angelEverywhere ? Appearance.angel.roundingLarge
            : root.liquidEverywhere ? Appearance.liquid.roundingLarge
            : root.inirEverywhere ? Appearance.inir.roundingLarge
            : Appearance.rounding.large
        // The liquid rim comes from LiquidGlassEdges; a second rectangular
        // border on top would double the edge.
        border.width: root.liquidEverywhere ? 0 : 1
        border.color: root.angelEverywhere ? Appearance.angel.colBorder
            : root.inirEverywhere ? Appearance.inir.colBorder
            : root.auroraEverywhere ? Appearance.aurora.colTooltipBorder
            : Appearance.colors.colLayer0Border
        clip: true

        layer.enabled: root.useWallpaperBackdrop
        layer.effect: GE.OpacityMask {
            maskSource: Rectangle {
                width: background.width
                height: background.height
                radius: background.radius
            }
        }

        Image {
            id: blurredWallpaper
            anchors.centerIn: parent
            width: root.screenWidth
            height: root.screenHeight
            visible: root.useWallpaperBackdrop
            // Loaded — but not painted — when only the shader wants it: an Image
            // is a texture provider regardless of visibility.
            source: (root.useWallpaperBackdrop || root.wantsRefractionTexture) ? root.wallpaperUrl : ""
            fillMode: Image.PreserveAspectCrop
            cache: true
            sourceSize.width: root.screenWidth
            sourceSize.height: root.screenHeight
            asynchronous: true

            layer.enabled: Appearance.effectsEnabled && root.useWallpaperBackdrop && root.visible
            layer.effect: MultiEffect {
                source: blurredWallpaper
                anchors.fill: source
                saturation: root.angelEverywhere
                    ? (Appearance.angel.blurSaturation * Appearance.angel.colorStrength)
                    : root.liquidEverywhere
                        ? Appearance.liquid.blurSaturation
                        : (Appearance.effectsEnabled ? 0.2 : 0)
                blurEnabled: Appearance.effectsEnabled
                blurMax: 64
                blur: Appearance.effectsEnabled
                    ? (root.angelEverywhere ? Appearance.angel.blurIntensity
                        : root.liquidEverywhere ? Appearance.liquid.blurIntensity
                        : 1)
                    : 0
            }

            Rectangle {
                anchors.fill: parent
                color: root.angelEverywhere
                    ? ColorUtils.transparentize(Appearance.colors.colLayer0Base, Appearance.angel.overlayOpacity)
                    : root.liquidEverywhere
                        ? ColorUtils.transparentize(Appearance.colors.colLayer0Base, Appearance.liquid.popupTransparentize)
                        : ColorUtils.transparentize(Appearance.colors.colLayer0Base, Appearance.aurora.popupTransparentize)
            }
        }

        LiquidGlassEdges {
            visible: root.liquidEverywhere && !Appearance.gameModeMinimal
            // Same treatment as GlassBackground: sheen over the surface, and
            // rim refraction from the (centered) wallpaper texture.
            sheenOverContent: root.useWallpaperBackdrop || root.realGlass
            surfaceRadius: background.radius
            backdropSource: blurredWallpaper.status === Image.Ready ? blurredWallpaper : null
            // The wallpaper image is centered on the panel, so the panel's
            // top-left sits at this offset inside it.
            backdropOrigin: Qt.point((root.screenWidth - background.width) / 2,
                                     (root.screenHeight - background.height) / 2)
            backdropScreen: Qt.size(root.screenWidth, root.screenHeight)
        }
    }

    // ═══ Content ═══
    ColumnLayout {
        id: contentColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: root.panelPadding
        spacing: 12

        // Header
        RowLayout {
            Layout.fillWidth: true
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("System Monitor")
                font.pixelSize: Appearance.font.pixelSize.larger
                font.weight: Font.Medium
                color: root.colText
            }
            StyledText {
                text: Translation.tr("Updated every %1s").arg(Math.round((Config.options?.resources?.updateInterval ?? 3000) / 1000))
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: root.colSubtext
            }
        }

        // Card grid
        GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: 12
            rowSpacing: 12

            // ── CPU (with per-core bars) ──
            StatCard {
                Layout.fillWidth: true
                Layout.columnSpan: 2
                icon: "memory"
                title: "CPU"
                valueText: Math.round(ResourceUsage.cpuUsage * 100) + "%"
                subText: ResourceUsage.maxAvailableCpuString + " · " + ResourceUsage.perCoreCpuUsage.length + " " + Translation.tr("cores")
                graphValues: ResourceUsage.cpuUsageHistory
                graphColor: root.colPrimary

                // Per-core mini bars
                Row {
                    id: coreRow
                    Layout.fillWidth: true
                    Layout.preferredHeight: 26
                    spacing: 2
                    visible: ResourceUsage.perCoreCpuUsage.length > 0

                    Repeater {
                        model: ResourceUsage.perCoreCpuUsage
                        delegate: Rectangle {
                            required property real modelData
                            width: Math.max(2, (coreRow.width - (coreRow.spacing * (ResourceUsage.perCoreCpuUsage.length - 1))) / ResourceUsage.perCoreCpuUsage.length)
                            height: coreRow.height
                            radius: 2
                            color: ColorUtils.transparentize(root.colPrimary, 0.88)

                            Rectangle {
                                anchors.bottom: parent.bottom
                                anchors.left: parent.left
                                anchors.right: parent.right
                                height: Math.max(2, parent.height * modelData)
                                radius: 2
                                color: root.colPrimary

                                Behavior on height {
                                    enabled: Appearance.animationsEnabled
                                    NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
                                }
                            }
                        }
                    }
                }
            }

            // ── RAM ──
            StatCard {
                Layout.fillWidth: true
                icon: "memory_alt"
                title: Translation.tr("Memory")
                valueText: Math.round(ResourceUsage.memoryUsedPercentage * 100) + "%"
                subText: ResourceUsage.kbToGbString(ResourceUsage.memoryUsed) + " / " + ResourceUsage.kbToGbString(ResourceUsage.memoryTotal)
                graphValues: ResourceUsage.memoryUsageHistory
                graphColor: root.colSecondary
            }

            // ── Swap ──
            StatCard {
                Layout.fillWidth: true
                visible: ResourceUsage.swapTotal > 1024
                icon: "swap_horiz"
                title: Translation.tr("Swap")
                valueText: Math.round(ResourceUsage.swapUsedPercentage * 100) + "%"
                subText: ResourceUsage.kbToGbString(ResourceUsage.swapUsed) + " / " + ResourceUsage.kbToGbString(ResourceUsage.swapTotal)
                graphValues: ResourceUsage.swapUsageHistory
                graphColor: root.colTertiary
            }

            // ── GPU ──
            StatCard {
                Layout.fillWidth: true
                icon: "planner_review"
                title: "GPU"
                valueText: Math.round(ResourceUsage.gpuUsage * 100) + "%"
                subText: ResourceUsage.gpuTemp > 0 ? ResourceUsage.gpuTemp + "°C" : ""
                graphValues: ResourceUsage.gpuUsageHistory
                graphColor: root.colPrimary
            }

            // ── VRAM ──
            StatCard {
                Layout.fillWidth: true
                visible: ResourceUsage.vramTotal > 0
                icon: "developer_board"
                title: "VRAM"
                valueText: Math.round(ResourceUsage.vramUsedPercentage * 100) + "%"
                subText: ResourceUsage.bytesToGbString(ResourceUsage.vramUsed) + " / " + ResourceUsage.bytesToGbString(ResourceUsage.vramTotal)
                progressValue: ResourceUsage.vramUsedPercentage
                progressColor: root.colSecondary
            }

            // ── Network ──
            StatCard {
                Layout.fillWidth: true
                icon: "swap_vert"
                title: Translation.tr("Network")
                valueText: ""
                subText: ""
                graphValues: ResourceUsage.networkRxHistory
                graphColor: root.colPrimary

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 16

                    RowLayout {
                        spacing: 5
                        MaterialSymbol { text: "arrow_downward"; iconSize: 14; color: root.colPrimary }
                        StyledText {
                            text: ResourceUsage.formatRate(ResourceUsage.networkRxRate)
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.family: Appearance.font.family.numbers
                            color: root.colText
                        }
                    }
                    RowLayout {
                        spacing: 5
                        MaterialSymbol { text: "arrow_upward"; iconSize: 14; color: root.colSecondary }
                        StyledText {
                            text: ResourceUsage.formatRate(ResourceUsage.networkTxRate)
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.family: Appearance.font.family.numbers
                            color: root.colText
                        }
                    }
                    Item { Layout.fillWidth: true }
                }
            }

            // ── Disk ──
            StatCard {
                Layout.fillWidth: true
                icon: "hard_drive"
                title: Translation.tr("Disk")
                valueText: Math.round(ResourceUsage.diskUsedPercentage * 100) + "%"
                subText: ResourceUsage.bytesToGbString(ResourceUsage.diskUsed) + " / " + ResourceUsage.bytesToGbString(ResourceUsage.diskTotal)
                    + "  ·  R " + ResourceUsage.formatRate(ResourceUsage.diskReadRate)
                    + "  W " + ResourceUsage.formatRate(ResourceUsage.diskWriteRate)
                progressValue: ResourceUsage.diskUsedPercentage
                progressColor: ResourceUsage.diskUsedPercentage > 0.9 ? root.colError : root.colPrimary
            }

            // ── Temperatures ──
            StatCard {
                Layout.fillWidth: true
                visible: ResourceUsage.cpuTemp > 0 || ResourceUsage.gpuTemp > 0
                icon: "thermostat"
                title: Translation.tr("Temperature")
                valueText: ResourceUsage.maxTemp + "°C"
                subText: {
                    let parts = []
                    if (ResourceUsage.cpuTemp > 0) parts.push("CPU " + ResourceUsage.cpuTemp + "°C")
                    if (ResourceUsage.gpuTemp > 0) parts.push("GPU " + ResourceUsage.gpuTemp + "°C")
                    return parts.join(" · ")
                }
                progressValue: ResourceUsage.tempPercentage
                progressColor: ResourceUsage.maxTemp >= ResourceUsage.tempWarningThreshold
                    ? root.colError
                    : ResourceUsage.maxTemp >= 60
                        ? root.colTertiary
                        : root.colPrimary
            }
        }
    }

    // ═══ Stat card component ═══
    component StatCard: ColumnLayout {
        id: card
        // Extra content declared at usage sites (per-core bars, network rates)
        // is appended inside the card, after the subtext
        default property alias extraContent: cardContent.data

        required property string icon
        required property string title
        property string valueText: ""
        property string subText: ""
        property list<real> graphValues: []
        property color graphColor: Appearance.colors.colPrimary
        property real progressValue: -1
        property color progressColor: Appearance.colors.colPrimary

        Layout.fillWidth: true
        spacing: 6

        // Card background
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: cardContent.implicitHeight + 20
            radius: root.cardRadius
            color: root.colCard

            ColumnLayout {
                id: cardContent
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 10
                spacing: 6

                // Header row
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    MaterialSymbol {
                        text: card.icon
                        iconSize: 18
                        color: card.graphColor
                    }
                    StyledText {
                        text: card.title
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.Medium
                        color: root.colText
                    }
                    Item { Layout.fillWidth: true }
                    StyledText {
                        visible: card.valueText !== ""
                        text: card.valueText
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.Bold
                        font.family: Appearance.font.family.numbers
                        color: card.graphColor
                    }
                }

                // History graph (normalized to the window's peak)
                Item {
                    visible: card.graphValues.length > 1
                    Layout.fillWidth: true
                    Layout.preferredHeight: 46

                    Graph {
                        anchors.fill: parent
                        property real maxValue: {
                            let max = 0
                            for (let i = 0; i < card.graphValues.length; i++) {
                                if (card.graphValues[i] > max) max = card.graphValues[i]
                            }
                            return max > 0 ? max : 1
                        }
                        values: {
                            let res = []
                            for (let i = 0; i < card.graphValues.length; i++) {
                                res.push(card.graphValues[i] / maxValue)
                            }
                            return res
                        }
                        color: card.graphColor
                        fillOpacity: 0.25
                        alignment: Graph.Alignment.Right
                    }
                }

                // Progress bar
                StyledProgressBar {
                    visible: card.progressValue >= 0
                    Layout.fillWidth: true
                    value: card.progressValue
                    highlightColor: card.progressColor
                    trackColor: ColorUtils.transparentize(root.colSubtext, 0.85)
                }

                // Subtext
                StyledText {
                    visible: card.subText !== ""
                    Layout.fillWidth: true
                    text: card.subText
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: root.colSubtext
                }
            }
        }
    }
}
