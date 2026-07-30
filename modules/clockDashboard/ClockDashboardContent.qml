pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.sidebarRight.calendar
import qs.modules.sidebarRight.events
import QtQuick
import QtQuick.Layouts
import Quickshell
import QtQuick.Effects
import Qt5Compat.GraphicalEffects as GE
import "../sidebarRight/calendar/calendar_layout.js" as CalendarLayout

// Clock dashboard content — big animated clock, calendar, upcoming events,
// hourly + multi-day weather forecast. Rendered inside DashboardWindow.
Item {
    id: root

    // Injected by DashboardWindow when present (blur alignment)
    property var dashboardScreen: null
    readonly property real screenWidth: dashboardScreen?.width ?? Quickshell.screens[0]?.width ?? 1920
    readonly property real screenHeight: dashboardScreen?.height ?? Quickshell.screens[0]?.height ?? 1080

    implicitWidth: 940
    implicitHeight: contentColumn.implicitHeight + 2 * panelPadding

    readonly property int panelPadding: 20

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
    readonly property color colPrimary: angelEverywhere ? Appearance.angel.colPrimary
        : liquidEverywhere ? Appearance.liquid.colPrimary
        : inirEverywhere ? Appearance.inir.colPrimary : Appearance.colors.colPrimary
    readonly property color colCard: angelEverywhere ? Appearance.angel.colGlassCard
        : liquidEverywhere ? Appearance.liquid.colGlassCard
        : inirEverywhere ? Appearance.inir.colLayer1
        : auroraEverywhere ? Appearance.aurora.colSubSurface
        : Appearance.colors.colLayer1
    readonly property color colCardHover: Appearance.colLayer1Hover
    readonly property real cardRadius: angelEverywhere ? Appearance.angel.roundingNormal
        : liquidEverywhere ? Appearance.liquid.roundingNormal
        : inirEverywhere ? Appearance.inir.roundingNormal : Appearance.rounding.normal

    readonly property string wallpaperUrl: Wallpapers.effectiveWallpaperUrl
    readonly property bool realGlass: Appearance.liquidRealGlass
    readonly property bool useWallpaperBackdrop: auroraEverywhere && !inirEverywhere
        && !Appearance.gameModeMinimal && wallpaperUrl.length > 0 && !realGlass

    // ── Second-precise clock (dashboard-local, doesn't touch the global service) ──
    property var now: new Date()
    Timer {
        interval: 1000
        repeat: true
        running: root.visible
        triggeredOnStart: true
        onTriggered: root.now = new Date()
    }

    readonly property var locale: {
        const envLocale = Quickshell.env("LC_TIME") || Quickshell.env("LC_ALL") || Quickshell.env("LANG") || ""
        const cleaned = (envLocale.split(".")[0] ?? "").split("@")[0] ?? ""
        return cleaned ? Qt.locale(cleaned) : Qt.locale()
    }

    // ── Events (merged local + external, next 7 days, deduped) ──
    property int _eventsTrigger: 0
    Connections {
        target: Events
        function onEventAdded(event) { root._eventsTrigger++ }
        function onEventRemoved(id) { root._eventsTrigger++ }
        function onEventUpdated(event) { root._eventsTrigger++ }
    }
    property int _externalTrigger: 0
    Connections {
        target: CalendarSync
        function onEventsUpdated() { root._externalTrigger++ }
    }

    readonly property var upcomingEvents: {
        root._eventsTrigger
        root._externalTrigger
        const seen = new Set()
        const result = []
        const now = new Date()
        const start = new Date(now)
        start.setHours(0, 0, 0, 0)
        for (let i = 0; i < 7 && result.length < 6; i++) {
            const d = new Date(start)
            d.setDate(d.getDate() + i)
            const dayEvents = CalendarLayout.mergedEventsForDate(Events, CalendarSync, d)
            for (const e of dayEvents) {
                if (result.length >= 6) break
                const key = (e.uid ?? e.id ?? e.title ?? "") + "|" + (e.startDate ?? e.dateTime ?? "")
                if (seen.has(key)) continue
                seen.add(key)
                if (!e.allDay && new Date(e.startDate ?? e.dateTime) < now) continue
                result.push(e)
            }
        }
        return result
    }

    // ── Events dialog state ──
    property var eventsDialogEditEvent: null
    property bool showEventsDialog: false

    // ── Weather follows the calendar selection ──
    // null means "no day picked" → show live current conditions.
    property var selectedWeatherDate: null

    function _dateKey(d: var): string {
        if (!d)
            return "";
        return "%1-%2-%3".arg(d.getFullYear()).arg(String(d.getMonth() + 1).padStart(2, '0')).arg(String(d.getDate()).padStart(2, '0'));
    }

    readonly property bool weatherShowsNow: {
        if (!root.selectedWeatherDate)
            return true;
        return root._dateKey(root.selectedWeatherDate) === root._dateKey(new Date());
    }
    // The forecast entry for the picked day, or null if it falls outside the
    // provider's window (only ~7 days exist).
    readonly property var selectedForecast: {
        if (root.weatherShowsNow)
            return null;
        const key = root._dateKey(root.selectedWeatherDate);
        for (const f of Weather.forecast) {
            if (f.date === key)
                return f;
        }
        return null;
    }
    readonly property bool weatherUnavailable: !root.weatherShowsNow && !root.selectedForecast

    // Forecast temperature range (for the range bars), computed once per update
    readonly property var forecastSlice: Weather.forecast.slice(0, 6)
    readonly property real forecastRangeMin: {
        let m = Infinity
        for (const f of root.forecastSlice) m = Math.min(m, f.tempMin)
        return m === Infinity ? 0 : m
    }
    readonly property real forecastRangeMax: {
        let m = -Infinity
        for (const f of root.forecastSlice) m = Math.max(m, f.tempMax)
        return m === -Infinity ? 1 : m
    }

    // ═══ Background ═══
    StyledRectangularShadow {
        target: background
        visible: !Appearance.inirEverywhere && !Appearance.gameModeMinimal
    }
    Rectangle {
        id: background
        anchors.fill: parent
        color: root.inirEverywhere ? Appearance.inir.colLayer0
            : root.auroraEverywhere ? ColorUtils.applyAlpha(Appearance.colors.colLayer0, Appearance.panelSurfaceAlpha)
            : Appearance.colors.colLayer0
        radius: root.angelEverywhere ? Appearance.angel.roundingLarge
            : root.liquidEverywhere ? Appearance.liquid.roundingLarge
            : root.inirEverywhere ? Appearance.inir.roundingLarge
            : Appearance.rounding.large
        border.width: 1
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
            source: root.useWallpaperBackdrop ? root.wallpaperUrl : ""
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
        }
    }

    // ═══ Content ═══
    ColumnLayout {
        id: contentColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: root.panelPadding
        spacing: 14

        // ── Header: big clock + current weather ──
        RowLayout {
            Layout.fillWidth: true
            spacing: 16

            // Big animated clock
            ColumnLayout {
                spacing: 0

                RowLayout {
                    spacing: 2

                    StyledText {
                        text: Qt.formatTime(root.now, "HH:mm")
                        font.pixelSize: 64
                        font.weight: Font.Bold
                        font.family: Appearance.font.family.numbers
                        color: root.colText
                        animateChange: true
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignBottom
                        Layout.bottomMargin: 10
                        text: ":" + Qt.formatTime(root.now, "ss")
                        font.pixelSize: 24
                        font.weight: Font.Medium
                        font.family: Appearance.font.family.numbers
                        color: root.colPrimary
                        animateChange: true
                    }
                }

                StyledText {
                    text: root.locale.toString(root.now, "dddd, d MMMM yyyy")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: root.colSubtext
                }
                StyledText {
                    text: Translation.tr("Uptime: %1").arg(DateTime.uptime)
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: root.colSubtext
                    opacity: 0.8
                }
            }

            Item { Layout.fillWidth: true }

            // Weather summary — live conditions, or the picked day's forecast.
            // Dimmed when the picked day is outside the forecast window.
            ColumnLayout {
                visible: Weather.enabled
                spacing: 2
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                opacity: root.weatherUnavailable ? 0.35 : 1

                Behavior on opacity {
                    enabled: Appearance.animationsEnabled
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Appearance.animation.elementMoveFast.type
                        easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                    }
                }

                // Which day these numbers describe, once it isn't just "now".
                StyledText {
                    Layout.alignment: Qt.AlignRight
                    visible: !root.weatherShowsNow
                    text: root.selectedWeatherDate
                        ? root.selectedWeatherDate.toLocaleDateString(Qt.locale(), "dddd, d MMMM")
                        : ""
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.DemiBold
                    color: root.colSubtext
                }

                RowLayout {
                    Layout.alignment: Qt.AlignRight
                    spacing: 10

                    MaterialSymbol {
                        text: Icons.getWeatherIcon(root.weatherShowsNow
                            ? (Weather.data?.wCode ?? "113")
                            : (root.selectedForecast?.wCode ?? "113"),
                            root.weatherShowsNow && Weather.isNightNow()) ?? "cloud"
                        iconSize: 44
                        color: root.colPrimary
                    }
                    ColumnLayout {
                        spacing: 0
                        StyledText {
                            text: root.weatherShowsNow
                                ? (Weather.data?.temp ?? "--")
                                : (root.selectedForecast
                                    ? Math.round(root.selectedForecast.tempMax) + Weather.tempUnit
                                    : "--")
                            font.pixelSize: 32
                            font.weight: Font.Bold
                            font.family: Appearance.font.family.numbers
                            color: root.colText
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignRight
                            text: root.weatherShowsNow
                                ? ((Weather.data?.description ?? "") + (Weather.showVisibleCity ? " · " + (Weather.data?.city ?? "") : ""))
                                : (root.selectedForecast
                                    ? Weather.describeWeather(root.selectedForecast.wCode)
                                    : Translation.tr("No forecast for this day"))
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: root.colSubtext
                        }
                    }
                }
                StyledText {
                    Layout.alignment: Qt.AlignRight
                    visible: root.weatherShowsNow || !!root.selectedForecast
                    text: root.weatherShowsNow
                        ? Translation.tr("Feels like %1 · Humidity %2 · Wind %3")
                            .arg(Weather.data?.tempFeelsLike ?? "--")
                            .arg(Weather.data?.humidity ?? "--")
                            .arg(Weather.data?.wind ?? "--")
                        : Translation.tr("High %1 · Low %2 · Rain %3%")
                            .arg(Math.round(root.selectedForecast?.tempMax ?? 0) + Weather.tempUnit)
                            .arg(Math.round(root.selectedForecast?.tempMin ?? 0) + Weather.tempUnit)
                            .arg(root.selectedForecast?.precipChance ?? 0)
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: root.colSubtext
                    opacity: 0.85
                }
            }
        }

        // ── Body: calendar + forecast/events column ──
        RowLayout {
            Layout.fillWidth: true
            spacing: 14

            // Calendar
            Rectangle {
                Layout.alignment: Qt.AlignTop
                Layout.preferredWidth: 400
                implicitHeight: calendarWidget.implicitHeight + 20
                radius: root.cardRadius
                color: root.colCard

                CalendarWidget {
                    id: calendarWidget
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 10
                    onOpenEventsDialog: editEvent => {
                        root.eventsDialogEditEvent = editEvent
                        root.showEventsDialog = true
                    }
                    // Picking a day retargets the weather panel to it.
                    onDaySelected: date => root.selectedWeatherDate = date
                }
            }

            // Right column: hourly + forecast + upcoming
            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                spacing: 12

                // Hourly strip
                ColumnLayout {
                    visible: Weather.enabled && Weather.hourly.length > 0
                    Layout.fillWidth: true
                    spacing: 6

                    StyledText {
                        text: Translation.tr("Next hours")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: Font.DemiBold
                        color: root.colSubtext
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Repeater {
                            model: Weather.hourly
                            delegate: Rectangle {
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: hourlyCol.implicitHeight + 14
                                radius: root.cardRadius
                                color: root.colCard

                                ColumnLayout {
                                    id: hourlyCol
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: 7
                                    spacing: 2

                                    StyledText {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: modelData.time
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        font.family: Appearance.font.family.numbers
                                        color: root.colSubtext
                                    }
                                    MaterialSymbol {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: Icons.getWeatherIcon(modelData.wCode, modelData.hour < 6 || modelData.hour >= 20) ?? "cloud"
                                        iconSize: 20
                                        color: root.colPrimary
                                    }
                                    StyledText {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: Math.round(modelData.temp) + "°"
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        font.weight: Font.Medium
                                        font.family: Appearance.font.family.numbers
                                        color: root.colText
                                    }
                                    RowLayout {
                                        Layout.alignment: Qt.AlignHCenter
                                        visible: modelData.precipChance >= 20
                                        spacing: 1
                                        MaterialSymbol {
                                            text: "water_drop"
                                            iconSize: 10
                                            color: root.colSubtext
                                            opacity: 0.9
                                        }
                                        StyledText {
                                            text: modelData.precipChance + "%"
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            color: root.colSubtext
                                            opacity: 0.9
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Daily forecast
                ColumnLayout {
                    visible: Weather.enabled && Weather.forecast.length > 0
                    Layout.fillWidth: true
                    spacing: 4

                    StyledText {
                        text: Translation.tr("Forecast")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: Font.DemiBold
                        color: root.colSubtext
                    }

                    Repeater {
                        model: root.forecastSlice
                        delegate: Item {
                            id: forecastRow
                            required property var modelData
                            required property int index
                            Layout.fillWidth: true
                            implicitHeight: 26

                            // Marks the row the weather panel is currently showing.
                            readonly property bool isPicked: !root.weatherShowsNow
                                && forecastRow.modelData.date === root._dateKey(root.selectedWeatherDate)

                            Rectangle {
                                anchors.fill: parent
                                anchors.leftMargin: -6
                                anchors.rightMargin: -6
                                visible: forecastRow.isPicked
                                radius: Appearance.rounding.verysmall
                                color: root.colPrimary
                                opacity: 0.13
                            }

                            RowLayout {
                                anchors.fill: parent
                                spacing: 8

                                StyledText {
                                    Layout.preferredWidth: 72
                                    text: forecastRow.modelData.dayLabel
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.weight: forecastRow.index === 0 ? Font.DemiBold : Font.Normal
                                    color: root.colText
                                }
                                MaterialSymbol {
                                    text: Icons.getWeatherIcon(forecastRow.modelData.wCode, false) ?? "cloud"
                                    iconSize: 17
                                    color: root.colPrimary
                                }
                                StyledText {
                                    Layout.preferredWidth: 42
                                    visible: forecastRow.modelData.precipChance >= 20
                                    text: forecastRow.modelData.precipChance + "%"
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    font.family: Appearance.font.family.numbers
                                    color: root.colSubtext
                                }
                                StyledText {
                                    Layout.preferredWidth: 34
                                    horizontalAlignment: Text.AlignRight
                                    text: Math.round(forecastRow.modelData.tempMin) + "°"
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.family: Appearance.font.family.numbers
                                    color: root.colSubtext
                                }
                                // Temperature range bar
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 6
                                    Layout.alignment: Qt.AlignVCenter
                                    radius: 3
                                    color: ColorUtils.transparentize(root.colSubtext, 0.85)

                                    Rectangle {
                                        radius: 3
                                        height: parent.height
                                        x: parent.width * ((forecastRow.modelData.tempMin - root.forecastRangeMin) / Math.max(1, root.forecastRangeMax - root.forecastRangeMin))
                                        width: parent.width * ((forecastRow.modelData.tempMax - forecastRow.modelData.tempMin) / Math.max(1, root.forecastRangeMax - root.forecastRangeMin))
                                        color: root.colPrimary
                                        opacity: 0.85
                                    }
                                }
                                StyledText {
                                    Layout.preferredWidth: 34
                                    horizontalAlignment: Text.AlignRight
                                    text: Math.round(forecastRow.modelData.tempMax) + "°"
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.weight: Font.Medium
                                    font.family: Appearance.font.family.numbers
                                    color: root.colText
                                }
                            }
                        }
                    }
                }

                // Upcoming events
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    RowLayout {
                        Layout.fillWidth: true
                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Upcoming")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.weight: Font.DemiBold
                            color: root.colSubtext
                        }
                        StyledText {
                            visible: root.upcomingEvents.length === 0
                            text: Translation.tr("Nothing scheduled")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: root.colSubtext
                            opacity: 0.7
                        }
                    }

                    Repeater {
                        model: root.upcomingEvents
                        delegate: CalendarEventRow {
                            required property var modelData
                            Layout.fillWidth: true
                            event: modelData
                            showDate: true
                            interactive: (modelData?.source ?? "local") === "local"
                            onClicked: {
                                root.eventsDialogEditEvent = modelData
                                root.showEventsDialog = true
                            }
                        }
                    }
                }
            }
        }
    }

    // ═══ In-panel events dialog overlay ═══
    // Loaded lazily and driven imperatively, matching the sidebar's ToggleDialog
    // pattern. WindowDialog only collapses itself inside onShowChanged, so a
    // dialog created eagerly with `show: false` never zeroes its height and
    // renders as an empty glass box over the dashboard.
    Loader {
        id: eventsDialogLoader
        anchors.fill: parent
        active: false

        readonly property bool shown: root.showEventsDialog

        // Loader is synchronous, so `item` is available immediately after
        // activating — no onItemChanged race to handle.
        onShownChanged: {
            if (shown) {
                active = true
                if (!item) return
                if (root.eventsDialogEditEvent) item.loadEvent(root.eventsDialogEditEvent)
                else item.resetForm()
                item.show = true
                item.forceActiveFocus()
            } else if (item) {
                item.show = false
                root.eventsDialogEditEvent = null
            }
        }

        sourceComponent: EventsDialog {}

        Connections {
            target: eventsDialogLoader.item
            function onDismiss(): void {
                root.showEventsDialog = false
                root.eventsDialogEditEvent = null
            }
        }
    }
}
