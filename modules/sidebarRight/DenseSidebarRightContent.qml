// DenseSidebarRightContent.qml
//
// Single-column, space-efficient sidebar layout:
//   1. Slim header (uptime + system actions)
//   2. Quick toggles (classic or android style, same as other layouts)
//   3. Notifications — capped to a fraction of the panel height
//   4. Calendar (month grid)
//   5. Upcoming events
//   6. Tools card — To Do / Notepad / Calculator in one tabbed section
//   7. Misc card — the remaining widgets (System / Timer / Screen Time)
//
// Compatible with all global styles: material, aurora, inir, angel.

import qs
import qs.services
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Hyprland
import QtQuick.Effects
import Qt5Compat.GraphicalEffects as GE

import qs.modules.sidebarRight.quickToggles
import qs.modules.sidebarRight.quickToggles.classicStyle
import qs.modules.sidebarRight.bluetoothDevices
import qs.modules.sidebarRight.nightLight
import qs.modules.sidebarRight.hotspot
import qs.modules.sidebarRight.volumeMixer
import qs.modules.sidebarRight.wifiNetworks
import qs.modules.sidebarRight.notifications

import qs.modules.sidebarRight.calendar
import qs.modules.sidebarRight.todo
import qs.modules.sidebarRight.pomodoro
import qs.modules.sidebarRight.notepad
import qs.modules.sidebarRight.calculator
import qs.modules.sidebarRight.sysmon
import qs.modules.sidebarRight.events
import qs.modules.sidebarRight.screenTime

Item {
    id: root

    // ── Public API (same as SidebarRightContent) ──────────────────
    property int sidebarWidth: Appearance.sizes.sidebarWidthRight
    property int sidebarPadding: 8
    property int screenWidth: 1920
    property int screenHeight: 1080
    property var panelScreen: null
    property bool panelVisible: false

    property bool showAudioOutputDialog: false
    property bool showAudioInputDialog: false
    property bool showBluetoothDialog: false
    property bool showEventsDialog: false
    property bool showHotspotDialog: false
    property bool showNightLightDialog: false
    property bool showWifiDialog: false
    property bool editMode: false
    property var eventsDialogEditEvent: null
    property bool reloadButtonEnabled: true
    property bool settingsButtonEnabled: true

    readonly property int densePadding: Math.max(4, Math.min(6, Math.round(sidebarPadding * 0.7)))
    readonly property int notificationCount: Notifications.list?.length ?? 0

    property int configVersion: 0
    Connections {
        target: Config
        function onConfigChanged() { root.configVersion++ }
    }

    // ── Tab models ────────────────────────────────────────────────
    property int toolsTab: Persistent.states?.sidebar?.denseGroup?.toolsTab ?? 0
    property int miscTab: Persistent.states?.sidebar?.denseGroup?.miscTab ?? 0

    readonly property var toolsTabs: {
        root.configVersion // Force dependency
        const enabled = Config.options?.sidebar?.right?.enabledWidgets ?? ["calendar", "todo", "notepad", "calculator", "sysmon", "timer"]
        const all = [
            { id: "todo",       icon: "done_outline", label: Translation.tr("To Do"),   component: todoComponent },
            { id: "notepad",    icon: "edit_note",    label: Translation.tr("Notes"),   component: notepadComponent },
            { id: "calculator", icon: "calculate",    label: Translation.tr("Calc"),    component: calculatorComponent },
        ]
        const filtered = all.filter(t => enabled.includes(t.id))
        return filtered.length > 0 ? filtered : all
    }

    readonly property var miscTabs: {
        root.configVersion // Force dependency
        const enabled = Config.options?.sidebar?.right?.enabledWidgets ?? ["calendar", "todo", "notepad", "calculator", "sysmon", "timer"]
        const all = [
            { id: "sysmon",     icon: "monitor_heart", label: Translation.tr("System"),      component: sysmonComponent },
            { id: "timer",      icon: "schedule",      label: Translation.tr("Timer"),       component: timerComponent },
            { id: "screentime", icon: "av_timer",      label: Translation.tr("Screen Time"), component: screenTimeComponent },
        ]
        return all.filter(t => {
            if (t.id === "screentime" && !(Config.options?.sidebar?.screenTime?.enable ?? false))
                return false
            return enabled.includes(t.id)
        })
    }

    function handleRequestedWidget(): void {
        const w = GlobalStates.sidebarRightRequestedWidget
        if (!w) return
        const tIdx = root.toolsTabs.findIndex(t => t.id === w)
        if (tIdx !== -1) Persistent.states.sidebar.denseGroup.toolsTab = tIdx
        const mIdx = root.miscTabs.findIndex(t => t.id === w)
        if (mIdx !== -1) Persistent.states.sidebar.denseGroup.miscTab = mIdx
        GlobalStates.sidebarRightRequestedWidget = ""
    }

    Component.onCompleted: {
        Notifications.ensureInitialized()
        handleRequestedWidget()
    }

    // ── Close dialogs when sidebar hides; external dialog requests ─
    Connections {
        target: GlobalStates
        function onSidebarRightOpenChanged() {
            if (!GlobalStates.sidebarRightOpen) {
                root.showWifiDialog        = false
                root.showBluetoothDialog   = false
                root.showEventsDialog      = false
                root.showAudioOutputDialog = false
                root.showAudioInputDialog  = false
                root.showNightLightDialog  = false
                root.showHotspotDialog     = false
                root.eventsDialogEditEvent = null
            }
        }
        function onRequestWifiDialogChanged() {
            if (GlobalStates.requestWifiDialog) {
                GlobalStates.requestWifiDialog = false
                if (!GlobalStates.sidebarRightOpen) GlobalStates.sidebarRightOpen = true
                root.showWifiDialog = true
            }
        }
        function onRequestBluetoothDialogChanged() {
            if (GlobalStates.requestBluetoothDialog) {
                GlobalStates.requestBluetoothDialog = false
                if (!GlobalStates.sidebarRightOpen) GlobalStates.sidebarRightOpen = true
                root.showBluetoothDialog = true
            }
        }
        function onSidebarRightRequestedWidgetChanged() {
            root.handleRequestedWidget()
        }
    }

    // ─────────────────────────────────────────────────────────────
    // Background (identical pattern to the other layouts)
    // ─────────────────────────────────────────────────────────────
    StyledRectangularShadow {
        target: bg
        visible: !Appearance.inirEverywhere && !Appearance.gameModeMinimal
    }

    Rectangle {
        id: bg
        anchors.fill: parent

        property bool cardStyle: Config.options?.sidebar?.cardStyle ?? false
        readonly property bool angelEverywhere:  Appearance.angelEverywhere
        readonly property bool auroraEverywhere: Appearance.auroraEverywhere
        readonly property bool inirEverywhere:   Appearance.inirEverywhere
        readonly property bool gameModeMinimal:  Appearance.gameModeMinimal

        readonly property string wallpaperUrl: {
            const _d1 = WallpaperListener.multiMonitorEnabled
            const _d2 = WallpaperListener.effectivePerMonitor
            const _d3 = Wallpapers.effectiveWallpaperUrl
            return WallpaperListener.wallpaperUrlForScreen(root.panelScreen)
        }
        readonly property bool realGlass: Appearance.liquidRealGlass
        readonly property bool useWallpaperBackdrop: root.panelVisible
            && auroraEverywhere
            && !inirEverywhere
            && !gameModeMinimal
            && wallpaperUrl.length > 0
            && !realGlass

        ColorQuantizer {
            id: bgQuant
            source: (Appearance.auroraEverywhere || Appearance.angelEverywhere) ? bg.wallpaperUrl : ""
            depth: 0
            rescaleSize: 10
        }
        readonly property color wallpaperDominantColor: bgQuant?.colors?.[0] ?? Appearance.colors.colPrimary
        readonly property QtObject blendedColors: AdaptedMaterialScheme {
            color: ColorUtils.mix(bg.wallpaperDominantColor, Appearance.colors.colPrimaryContainer, 0.8)
                   || Appearance.m3colors.m3secondaryContainer
        }
        readonly property color colDarkSurface: angelEverywhere
            ? ColorUtils.transparentize(Appearance.angel.colGlassCard, 0.76)
            : inirEverywhere ? ColorUtils.transparentize(Appearance.inir.colLayer1, 0.22)
            : auroraEverywhere ? ColorUtils.transparentize(
                (blendedColors?.colLayer0 ?? Appearance.colors.colLayer0Base),
                Math.max(0.10, Appearance.aurora.subSurfaceTransparentize - 0.16)
            )
            : ColorUtils.transparentize(Appearance.colors.colLayer1, 0.22)

        color: gameModeMinimal  ? "transparent"
             : inirEverywhere   ? (cardStyle ? Appearance.inir.colLayer1 : Appearance.inir.colLayer0)
             : auroraEverywhere ? ColorUtils.applyAlpha((blendedColors?.colLayer0 ?? Appearance.colors.colLayer0), Appearance.panelSurfaceAlpha)
             : (cardStyle ? Appearance.colors.colLayer1 : Appearance.colors.colLayer0)

        border.width: gameModeMinimal ? 0 : (angelEverywhere ? Appearance.angel.panelBorderWidth : 1)
        border.color: angelEverywhere  ? Appearance.angel.colPanelBorder
                    : inirEverywhere   ? Appearance.inir.colBorder
                    : Appearance.colors.colLayer0Border

        radius: angelEverywhere  ? Appearance.angel.roundingNormal
              : Appearance.liquidEverywhere ? Appearance.liquid.roundingNormal
              : inirEverywhere   ? (cardStyle ? Appearance.inir.roundingLarge : Appearance.inir.roundingNormal)
              : cardStyle        ? Appearance.rounding.normal
              : (Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 1)
        clip: true

        layer.enabled: !gameModeMinimal && (root.panelVisible || !auroraEverywhere)
        layer.effect: GE.OpacityMask {
            maskSource: Rectangle {
                width: bg.width; height: bg.height; radius: bg.radius
            }
        }

        // Aurora blurred wallpaper
        Image {
            id: bgBlurWallpaper
            x: -(root.screenWidth - bg.width - Appearance.sizes.hyprlandGapsOut)
            y: -Appearance.sizes.hyprlandGapsOut
            width:  root.screenWidth  ?? 1920
            height: root.screenHeight ?? 1080
            visible: bg.useWallpaperBackdrop
            source: bg.useWallpaperBackdrop ? bg.wallpaperUrl : ""
            fillMode: Image.PreserveAspectCrop
            cache: true; asynchronous: true
            sourceSize.width: root.screenWidth ?? 1920
            sourceSize.height: root.screenHeight ?? 1080
            // OPTIMIZATION: Release FBO when sidebar is hidden (saves ~16 MiB VRAM)
            layer.enabled: Appearance.effectsEnabled && bg.useWallpaperBackdrop && root.panelVisible
            layer.effect: MultiEffect {
                source: bgBlurWallpaper
                anchors.fill: source
                saturation: bg.angelEverywhere
                    ? (Appearance.angel.blurSaturation * Appearance.angel.colorStrength)
                    : Appearance.liquidEverywhere
                        ? Appearance.liquid.blurSaturation
                        : (Appearance.effectsEnabled ? 0.2 : 0)
                blurEnabled: Appearance.effectsEnabled
                blurMax: 64
                blur: Appearance.effectsEnabled
                    ? (bg.angelEverywhere ? Appearance.angel.blurIntensity
                        : Appearance.liquidEverywhere ? Appearance.liquid.blurIntensity
                        : 1) : 0
            }
            Rectangle {
                anchors.fill: parent
                color: bg.angelEverywhere
                    ? ColorUtils.transparentize((bg.blendedColors?.colLayer0 ?? Appearance.colors.colLayer0Base),
                                               Appearance.angel.overlayOpacity * Appearance.angel.panelTransparentize)
                    : Appearance.liquidEverywhere
                        ? ColorUtils.transparentize((bg.blendedColors?.colLayer0 ?? Appearance.colors.colLayer0Base),
                                               Appearance.liquid.panelTransparentize)
                        : ColorUtils.transparentize((bg.blendedColors?.colLayer0 ?? Appearance.colors.colLayer0Base),
                                               Appearance.aurora.overlayTransparentize)
            }
        }

        // Liquid glass decorations — sheen + edge highlight
        LiquidGlassEdges {
            visible: Appearance.liquidEverywhere && !bg.gameModeMinimal
        }

        // Angel inset glow — top edge
        Rectangle {
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height:  Appearance.angel.insetGlowHeight
            visible: bg.angelEverywhere
            color:   Appearance.angel.colInsetGlow
            z: 10
        }

        AngelPartialBorder { targetRadius: bg.radius; z: 10 }

        // ─────────────────────────────────────────────────────────
        // Content column
        // ─────────────────────────────────────────────────────────
        ColumnLayout {
            id: contentColumn
            anchors.fill: parent
            anchors.margins: root.sidebarPadding
            spacing: root.densePadding

            // ── 0. Slim header: uptime + system actions ──────────
            RowLayout {
                Layout.fillWidth: true
                spacing: root.densePadding

                CustomIcon {
                    width: 20
                    height: 20
                    source: SystemInfo.distroIcon
                    colorize: true
                    color: bg.angelEverywhere ? Appearance.angel.colText : Appearance.colors.colOnLayer0
                }
                StyledText {
                    Layout.fillWidth: true
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: bg.angelEverywhere ? Appearance.angel.colText : Appearance.colors.colOnLayer0
                    elide: Text.ElideRight
                    text: Translation.tr("Up %1").arg(DateTime.uptime)
                }

                ButtonGroup {
                    padding: 2
                    spacing: 4
                    color: bg.angelEverywhere ? Appearance.angel.colGlassCard
                        : bg.auroraEverywhere ? Appearance.aurora.colSubSurface
                        : Appearance.colors.colLayer1

                    QuickToggleButton {
                        toggled: root.editMode
                        visible: (Config.options?.sidebar?.quickToggles?.style ?? "classic") === "android"
                        buttonIcon: "edit"
                        baseWidth: 34; baseHeight: 34
                        onClicked: root.editMode = !root.editMode
                        StyledToolTip { position: "left"; text: Translation.tr("Edit quick toggles") }
                    }
                    QuickToggleButton {
                        toggled: false
                        buttonIcon: "view_sidebar"
                        baseWidth: 34; baseHeight: 34
                        onClicked: Config.setNestedValue("sidebar.layout", "default")
                        StyledToolTip { position: "left"; text: Translation.tr("Switch to default layout") }
                    }
                    QuickToggleButton {
                        toggled: false
                        enabled: root.reloadButtonEnabled
                        opacity: enabled ? 1.0 : 0.5
                        buttonIcon: "restart_alt"
                        baseWidth: 34; baseHeight: 34
                        onClicked: root.doReload()
                        StyledToolTip { position: "left"; text: Translation.tr("Reload Quickshell") }
                    }
                    QuickToggleButton {
                        toggled: false
                        enabled: root.settingsButtonEnabled
                        opacity: enabled ? 1.0 : 0.5
                        buttonIcon: "settings"
                        baseWidth: 34; baseHeight: 34
                        onClicked: root.doSettings()
                        StyledToolTip { position: "left"; text: Translation.tr("Settings") }
                    }
                    QuickToggleButton {
                        toggled: false
                        buttonIcon: "power_settings_new"
                        baseWidth: 34; baseHeight: 34
                        onClicked: GlobalStates.sessionOpen = true
                        StyledToolTip { position: "left"; text: Translation.tr("Session") }
                    }
                }
            }

            // ── 1. Quick sliders (optional) ──────────────────────
            Loader {
                Layout.fillWidth: true
                visible: active
                active: {
                    const cfg = Config.options?.sidebar?.quickSliders
                    if (!cfg?.enable) return false
                    return (cfg?.showMic || cfg?.showVolume || cfg?.showBrightness) ?? false
                }
                sourceComponent: QuickSliders {}
            }

            // ── 2. Quick toggles ─────────────────────────────────
            QuickPanelLoader {
                styleName: "classic"
                sourceComponent: ClassicQuickPanel {}
            }
            QuickPanelLoader {
                styleName: "android"
                sourceComponent: AndroidQuickPanel {
                    editMode: root.editMode
                }
            }

            // ── 3. Notifications (capped height) ─────────────────
            DenseCard {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.preferredHeight: Math.max(100, Math.round(bg.height * 0.14))

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: root.densePadding
                    spacing: 2

                    DenseSectionHeader {
                        headerIcon: "notifications"
                        headerText: Translation.tr("Notifications")
                        badgeText: root.notificationCount > 0 ? root.notificationCount.toString() : ""

                        DenseHeaderButton {
                            buttonIcon: Notifications.silent ? "notifications_off" : "notifications_active"
                            toggled: Notifications.silent
                            tooltipText: Notifications.silent ? Translation.tr("Unmute notifications") : Translation.tr("Mute notifications")
                            onClicked: Notifications.silent = !Notifications.silent
                        }
                        DenseHeaderButton {
                            visible: root.notificationCount > 0
                            buttonIcon: "delete_sweep"
                            tooltipText: Translation.tr("Clear all notifications")
                            onClicked: Notifications.discardAllNotifications()
                        }
                    }

                    NotificationList {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                    }
                }
            }

            // ── 4. Calendar ──────────────────────────────────────
            DenseCard {
                Layout.fillWidth: true
                Layout.fillHeight: false
                implicitHeight: denseCalendar.implicitHeight + root.densePadding * 2

                CalendarWidget {
                    id: denseCalendar
                    anchors.fill: parent
                    anchors.margins: root.densePadding
                    onOpenEventsDialog: (editEvent) => {
                        root.eventsDialogEditEvent = editEvent
                        root.showEventsDialog = true
                    }
                }
            }

            // ── 5. Upcoming events ───────────────────────────────
            DenseCard {
                id: eventsCard
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.preferredHeight: Math.max(84, Math.round(bg.height * 0.11))

                // Merged upcoming events (next 14 days, local + external)
                property int _eventsTrigger: 0
                Connections {
                    target: Events
                    function onEventAdded(event) { eventsCard._eventsTrigger++ }
                    function onEventRemoved(id) { eventsCard._eventsTrigger++ }
                    function onEventUpdated(event) { eventsCard._eventsTrigger++ }
                }
                property int _externalTrigger: 0
                Connections {
                    target: CalendarSync
                    function onEventsUpdated() { eventsCard._externalTrigger++ }
                }
                readonly property var upcomingEvents: {
                    const _t = _eventsTrigger
                    const _t2 = _externalTrigger
                    const now = new Date()
                    const local = Events.getUpcomingEvents(14).map(e => Object.assign({}, e, { _source: "local" }))
                    const startDay = new Date(now); startDay.setHours(0,0,0,0)
                    const ext = []
                    for (let i = 0; i < 14; i++) {
                        const d = new Date(startDay); d.setDate(d.getDate() + i)
                        const dayEvts = CalendarSync.getEventsForDate(d) || []
                        for (const e of dayEvts) {
                            const evtTime = new Date(e.startDate || e.dateTime)
                            if (evtTime >= now || (e.allDay && evtTime >= startDay))
                                ext.push(Object.assign({}, e, { _source: "external", dateTime: e.startDate || e.dateTime, category: "general", priority: "normal" }))
                        }
                    }
                    const all = local.concat(ext)
                    all.sort((a,b) => new Date(a.dateTime || a.startDate) - new Date(b.dateTime || b.startDate))
                    return all
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: root.densePadding
                    spacing: 2

                    DenseSectionHeader {
                        headerIcon: "event_upcoming"
                        headerText: Translation.tr("Upcoming")

                        DenseHeaderButton {
                            buttonIcon: "add"
                            tooltipText: Translation.tr("Add event")
                            onClicked: {
                                root.eventsDialogEditEvent = null
                                root.showEventsDialog = true
                            }
                        }
                    }

                    Flickable {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentHeight: upcomingCol.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                        ColumnLayout {
                            id: upcomingCol
                            width: parent.width
                            spacing: 2

                            Repeater {
                                model: eventsCard.upcomingEvents.slice(0, 12)
                                delegate: EventCard {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    event: modelData
                                    isExternal: (modelData?._source ?? "local") === "external"
                                    onEditClicked: (evt) => {
                                        if (!isExternal) {
                                            root.eventsDialogEditEvent = evt
                                            root.showEventsDialog = true
                                        }
                                    }
                                    onRemoveClicked: {
                                        if (!isExternal) Events.removeEvent(modelData.id)
                                    }
                                }
                            }

                            StyledText {
                                Layout.fillWidth: true
                                visible: eventsCard.upcomingEvents.length === 0
                                horizontalAlignment: Text.AlignHCenter
                                topPadding: 12
                                text: Translation.tr("No upcoming events")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: bg.inirEverywhere ? Appearance.inir.colTextSecondary
                                    : bg.angelEverywhere ? Appearance.angel.colTextSecondary
                                    : Appearance.colors.colSubtext
                            }
                        }
                    }
                }
            }

            // ── 6. Tools: To Do / Notes / Calculator ─────────────
            TabbedCard {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 90
                tabs: root.toolsTabs
                currentIndex: root.toolsTab
                onTabClicked: (index) => Persistent.states.sidebar.denseGroup.toolsTab = index
            }

            // ── 7. Misc: remaining widgets ───────────────────────
            TabbedCard {
                visible: root.miscTabs.length > 0
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 90
                tabs: root.miscTabs
                currentIndex: root.miscTab
                onTabClicked: (index) => Persistent.states.sidebar.denseGroup.miscTab = index
            }
        }
    }

    // ── Widget components ─────────────────────────────────────────
    Component { id: todoComponent;       TodoWidget {} }
    Component { id: notepadComponent;    NotepadWidget {} }
    Component {
        id: calculatorComponent
        CalculatorWidget {
            compactMode: true
            centerContentVertically: true
        }
    }
    Component { id: sysmonComponent;     SysMonWidget {} }
    Component {
        id: timerComponent
        PomodoroWidget { compactMode: true }
    }
    Component { id: screenTimeComponent; ScreenTimeWidget {} }

    // ── Dialogs (identical to the other layouts) ──────────────────
    ToggleDialog {
        shownPropertyString: "showAudioOutputDialog"
        dialog: VolumeDialog { isSink: true }
    }
    ToggleDialog {
        shownPropertyString: "showAudioInputDialog"
        dialog: VolumeDialog { isSink: false }
    }
    ToggleDialog {
        shownPropertyString: "showBluetoothDialog"
        dialog: BluetoothDialog {}
        onShownChanged: {
            if (!Bluetooth.defaultAdapter) return
            if (!shown) {
                Bluetooth.defaultAdapter.discovering = false
            } else {
                Bluetooth.defaultAdapter.enabled = true
                Bluetooth.defaultAdapter.discovering = true
            }
        }
    }
    ToggleDialog {
        shownPropertyString: "showNightLightDialog"
        dialog: NightLightDialog {}
    }
    ToggleDialog {
        shownPropertyString: "showHotspotDialog"
        dialog: HotspotDialog {}
    }
    ToggleDialog {
        shownPropertyString: "showWifiDialog"
        dialog: WifiDialog {}
        onShownChanged: {
            if (!shown) return
            Network.enableWifi()
            Network.rescanWifi()
        }
    }
    ToggleDialog {
        id: denseEventsToggle
        shownPropertyString: "showEventsDialog"
        dialog: EventsDialog {}
        onShownChanged: {
            if (shown && denseEventsToggle.item) {
                if (root.eventsDialogEditEvent) {
                    denseEventsToggle.item.loadEvent(root.eventsDialogEditEvent)
                } else {
                    denseEventsToggle.item.resetForm()
                }
            }
        }
        onActiveChanged: {
            if (!active) {
                root.eventsDialogEditEvent = null
            }
        }
    }

    // ── Cooldown timers + system actions ──────────────────────────
    Timer { id: reloadCooldown;   interval: 500; onTriggered: root.reloadButtonEnabled  = true }
    Timer { id: settingsCooldown; interval: 500; onTriggered: root.settingsButtonEnabled = true }

    function doReload() {
        if (!root.reloadButtonEnabled) return
        root.reloadButtonEnabled = false
        reloadCooldown.restart()
        if (CompositorService.isHyprland)
            CompositorService.hyprDispatch("reload")
        else if (CompositorService.isNiri)
            Quickshell.execDetached(["/usr/bin/niri", "msg", "action", "load-config-file"])
        Quickshell.execDetached(["/usr/bin/bash", Quickshell.shellPath("scripts/restart-shell.sh")])
    }

    function doSettings() {
        if (!root.settingsButtonEnabled) return
        root.settingsButtonEnabled = false
        settingsCooldown.restart()
        if (CompositorService.isNiri) {
            const wins = NiriService.windows || []
            for (let i = 0; i < wins.length; i++) {
                const w = wins[i]
                if (w.title === "illogical-impulse Settings" && w.app_id === "org.quickshell") {
                    GlobalStates.sidebarRightOpen = false
                    Qt.callLater(() => NiriService.focusWindow(w.id))
                    return
                }
            }
        }
        GlobalStates.sidebarRightOpen = false
        Qt.callLater(() => Quickshell.execDetached([Quickshell.shellPath("scripts/inir"), "settings"]))
    }

    // ═════════════════════════════════════════════════════════════
    // INLINE COMPONENTS
    // ═════════════════════════════════════════════════════════════

    component QuickPanelLoader: Loader {
        id: qpLoader
        required property string styleName
        Layout.alignment: item?.Layout.alignment ?? Qt.AlignHCenter
        Layout.fillWidth: item?.Layout.fillWidth ?? false
        visible: active
        active: (Config.options?.sidebar?.quickToggles?.style ?? "classic") === styleName
        Connections {
            target: qpLoader.item
            ignoreUnknownSignals: true
            function onOpenAudioOutputDialog() { root.showAudioOutputDialog = true }
            function onOpenAudioInputDialog()  { root.showAudioInputDialog  = true }
            function onOpenBluetoothDialog()   { root.showBluetoothDialog   = true }
            function onOpenNightLightDialog()  { root.showNightLightDialog  = true }
            function onOpenHotspotDialog()     { root.showHotspotDialog     = true }
            function onOpenWifiDialog()        { root.showWifiDialog        = true }
        }
    }

    component DenseCard: Rectangle {
        radius: bg.angelEverywhere ? Appearance.angel.roundingNormal
            : bg.inirEverywhere ? Appearance.inir.roundingNormal
            : Appearance.rounding.normal
        color: bg.angelEverywhere ? Appearance.angel.colGlassCard
            : bg.inirEverywhere ? Appearance.inir.colLayer1
            : bg.colDarkSurface
        border.width: bg.inirEverywhere ? 1 : 0
        border.color: bg.inirEverywhere ? Appearance.inir.colBorder : "transparent"
        clip: true
    }

    component DenseSectionHeader: RowLayout {
        id: denseHeader
        property string headerIcon: ""
        property string headerText: ""
        property string badgeText: ""
        Layout.fillWidth: true
        spacing: 5

        MaterialSymbol {
            visible: denseHeader.headerIcon !== ""
            text: denseHeader.headerIcon
            iconSize: 15
            fill: 1
            color: bg.inirEverywhere  ? Appearance.inir.colPrimary
                 : bg.angelEverywhere ? Appearance.angel.colPrimary
                 : Appearance.colors.colPrimary
        }
        StyledText {
            Layout.fillWidth: true
            text: denseHeader.headerText
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: Font.Medium
            color: bg.inirEverywhere  ? Appearance.inir.colText
                 : bg.angelEverywhere ? Appearance.angel.colText
                 : Appearance.colors.colOnLayer1
        }
        Rectangle {
            visible: denseHeader.badgeText !== ""
            implicitWidth: Math.max(16, denseBadgeLabel.implicitWidth + 8)
            implicitHeight: 16
            radius: 8
            color: bg.inirEverywhere  ? Appearance.inir.colSecondaryContainer
                 : bg.angelEverywhere ? ColorUtils.transparentize(Appearance.angel.colPrimary, 0.70)
                 : Appearance.colors.colSecondaryContainer
            StyledText {
                id: denseBadgeLabel
                anchors.centerIn: parent
                text: denseHeader.badgeText
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.weight: Font.Bold
                font.family: Appearance.font.family.numbers
                color: bg.inirEverywhere  ? Appearance.inir.colOnSecondaryContainer
                     : bg.angelEverywhere ? Appearance.angel.colOnPrimary
                     : Appearance.m3colors.m3onSecondaryContainer
            }
        }
    }

    component DenseHeaderButton: RippleButton {
        id: dhBtn
        property string buttonIcon
        property string tooltipText: ""
        implicitWidth: 24
        implicitHeight: 24
        buttonRadius: bg.angelEverywhere ? Appearance.angel.roundingSmall
            : bg.inirEverywhere ? Appearance.inir.roundingSmall : 12
        colBackground: "transparent"
        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            text: dhBtn.buttonIcon
            iconSize: 15
            fill: dhBtn.toggled ? 1 : 0
            color: dhBtn.toggled
                ? (bg.inirEverywhere  ? Appearance.inir.colPrimary
                 : bg.angelEverywhere ? Appearance.angel.colPrimary
                 : Appearance.colors.colPrimary)
                : (bg.inirEverywhere  ? Appearance.inir.colTextSecondary
                 : bg.angelEverywhere ? Appearance.angel.colTextSecondary
                 : Appearance.colors.colSubtext)
        }
        StyledToolTip {
            visible: dhBtn.buttonHovered && dhBtn.tooltipText !== ""
            text: dhBtn.tooltipText
        }
    }

    component TabbedCard: DenseCard {
        id: tabCard
        property var tabs: []
        property int currentIndex: 0
        signal tabClicked(int index)
        readonly property int clampedIndex: Math.max(0, Math.min(currentIndex, tabs.length - 1))

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: root.densePadding
            spacing: 2

            RowLayout {
                Layout.fillWidth: true
                spacing: 2

                Repeater {
                    model: tabCard.tabs
                    delegate: RippleButton {
                        id: tabBtn
                        required property int index
                        required property var modelData
                        readonly property bool isActive: tabCard.clampedIndex === index
                        implicitHeight: 26
                        implicitWidth: tabBtnRow.implicitWidth + 14
                        buttonRadius: Appearance.rounding.full
                        toggled: isActive
                        colBackgroundToggled: bg.inirEverywhere ? Appearance.inir.colSecondaryContainer
                            : bg.angelEverywhere ? ColorUtils.transparentize(Appearance.angel.colPrimary, 0.60)
                            : Appearance.colors.colSecondaryContainer
                        colBackgroundToggledHover: colBackgroundToggled
                        onClicked: tabCard.tabClicked(tabBtn.index)

                        contentItem: RowLayout {
                            id: tabBtnRow
                            anchors.centerIn: parent
                            spacing: 4
                            MaterialSymbol {
                                text: tabBtn.modelData.icon
                                iconSize: 15
                                fill: tabBtn.isActive ? 1 : 0
                                animateFill: true
                                color: tabBtn.isActive
                                    ? (bg.inirEverywhere  ? Appearance.inir.colOnSecondaryContainer
                                     : bg.angelEverywhere ? Appearance.angel.colOnPrimary
                                     : Appearance.m3colors.m3onSecondaryContainer)
                                    : (bg.inirEverywhere  ? Appearance.inir.colTextSecondary
                                     : bg.angelEverywhere ? Appearance.angel.colTextSecondary
                                     : Appearance.colors.colSubtext)
                            }
                            StyledText {
                                visible: tabBtn.isActive
                                text: tabBtn.modelData.label
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.Medium
                                color: bg.inirEverywhere  ? Appearance.inir.colOnSecondaryContainer
                                     : bg.angelEverywhere ? Appearance.angel.colOnPrimary
                                     : Appearance.m3colors.m3onSecondaryContainer
                            }
                        }
                        StyledToolTip {
                            visible: tabBtn.buttonHovered && !tabBtn.isActive
                            text: tabBtn.modelData.label
                        }
                    }
                }

                Item { Layout.fillWidth: true }
            }

            StackLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: tabCard.clampedIndex

                Repeater {
                    model: tabCard.tabs
                    delegate: Loader {
                        required property var modelData
                        active: StackLayout.isCurrentItem
                        sourceComponent: modelData.component
                    }
                }
            }
        }
    }

    component ToggleDialog: Loader {
        id: tdLoader
        required property string shownPropertyString
        property alias dialog: tdLoader.sourceComponent
        readonly property bool shown: root[shownPropertyString]
        anchors.fill: parent
        active: shown
        onItemChanged: {
            if (item) { item.show = true; item.forceActiveFocus() }
        }
        Connections {
            target: tdLoader.item
            ignoreUnknownSignals: true
            function onDismiss() { root[tdLoader.shownPropertyString] = false }
        }
    }
}
