import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import QtQuick.Effects
import QtMultimedia
import Qt5Compat.GraphicalEffects
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import Quickshell.Services.Mpris
import Quickshell.Services.SystemTray
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.models
import qs.modules.common.functions
import qs.modules.bar as Bar
import qs.modules.background.widgets.clock as BackgroundClock
import Quickshell
import Quickshell.Services.SystemTray

MouseArea {
    id: root
    required property LockContext context
    
    // States: "clock" (initial view) or "login" (password entry)
    property string currentView: "clock"
    // Show login view when explicitly switched OR when there's password text
    property bool showLoginView: currentView === "login"
    property bool hasAttemptedUnlock: false
    property bool oskVisible: false
    
    readonly property bool requirePasswordToPower: Config.options?.lock?.security?.requirePasswordToPower ?? true
    readonly property bool blurEnabled: Config.options?.lock?.blur?.enable ?? true
    readonly property bool useSafeBlurPipeline: CompositorService.isNiri
    readonly property real blurAmount: 0.8
    readonly property real blurRadius: Config.options?.lock?.blur?.radius ?? 64
    readonly property real blurZoom: Config.options?.lock?.blur?.extraZoom ?? 1.1
    readonly property bool enableAnimation: Config.options?.lock?.enableAnimation ?? false

    // Screensaver config
    readonly property bool screensaverEnabled: Config.options?.lock?.screensaver?.enable ?? true
    readonly property int screensaverIdleSeconds: Config.options?.lock?.screensaver?.idleSeconds ?? 30
    readonly property int screensaverWallpaperInterval: Config.options?.lock?.screensaver?.wallpaperIntervalSeconds ?? 30
    readonly property bool screensaverShowClock: Config.options?.lock?.screensaver?.showClock ?? true
    property bool screensaverActive: false

    function safeLockNotificationImage(source): string {
        const value = String(source ?? "")
        return value.startsWith("image://qsimage/") ? "" : value
    }
    // Wallpaper path resolution
    readonly property string _wallpaperSource: Config.options?.background?.wallpaperPath ?? ""
    readonly property string _wallpaperThumbnail: Config.options?.background?.thumbnailPath ?? ""
    readonly property bool wallpaperIsVideo: {
        const lp = _wallpaperSource.toLowerCase();
        return lp.endsWith(".mp4") || lp.endsWith(".webm") || lp.endsWith(".mkv") || lp.endsWith(".avi") || lp.endsWith(".mov");
    }
    readonly property bool wallpaperIsGif: _wallpaperSource.toLowerCase().endsWith(".gif")
    // Static image source: use raw path for normal wallpapers, thumbnail for video/gif
    readonly property string _staticWallpaperPath: {
        if (!_wallpaperSource) return "";
        if (wallpaperIsVideo || wallpaperIsGif) return _wallpaperThumbnail || _wallpaperSource;
        return _wallpaperSource;
    }
    
    // Safe fallback background color (prevents red screen on errors)
    Rectangle {
        anchors.fill: parent
        color: Appearance.colors.colLayer0
        z: -1
    }
    
    // Static background wallpaper with blur (fallback for video/gif when animation disabled, or primary for static wallpapers)
    Image {
        id: backgroundWallpaper
        anchors.fill: parent
        // Drop source on the safe blur path so the FastBlur layer never
        // allocates a shader on Niri (where the MultiEffect path is the
        // only renderer used).  Some GPU drivers leak a red buffer when the
        // FastBlur shader fails to load even on an invisible item.
        source: root.useSafeBlurPipeline ? "" : root._staticWallpaperPath
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        visible: !root.wallpaperIsGif && !root.wallpaperIsVideo && !root.useSafeBlurPipeline
        
        layer.enabled: root.blurEnabled && !root.useSafeBlurPipeline
        layer.effect: FastBlur {
            radius: root.blurRadius
        }
        
        transform: Scale {
            origin.x: backgroundWallpaper.width / 2
            origin.y: backgroundWallpaper.height / 2
            xScale: root.blurEnabled ? root.blurZoom : 1
            yScale: root.blurEnabled ? root.blurZoom : 1
        }
    }

    Image {
        id: backgroundWallpaperSource
        anchors.fill: parent
        source: root.useSafeBlurPipeline && !root.wallpaperIsGif && !root.wallpaperIsVideo ? root._staticWallpaperPath : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        visible: false
        z: -2
    }
    
    // Animated GIF wallpaper
    // Shows first frame when enableAnimation is false, plays when true
    AnimatedImage {
        id: gifWallpaper
        anchors.fill: parent
        visible: root.wallpaperIsGif && !root.useSafeBlurPipeline
        // Same red-buffer guard as backgroundWallpaper above.
        source: (root.wallpaperIsGif && !root.useSafeBlurPipeline) ? root._wallpaperSource : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        playing: visible && root.enableAnimation
        
        layer.enabled: root.blurEnabled && !root.useSafeBlurPipeline
        layer.effect: FastBlur {
            radius: root.blurRadius
        }
        
        transform: Scale {
            origin.x: gifWallpaper.width / 2
            origin.y: gifWallpaper.height / 2
            xScale: root.blurEnabled ? root.blurZoom : 1
            yScale: root.blurEnabled ? root.blurZoom : 1
        }
    }

    AnimatedImage {
        id: gifWallpaperSource
        anchors.fill: parent
        source: root.useSafeBlurPipeline && root.wallpaperIsGif ? root._wallpaperSource : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        playing: root.enableAnimation
        visible: false
        z: -2
    }
    
    // Video wallpaper
    // Shows first frame (paused) when enableAnimation is false, plays when true
    Video {
        id: videoWallpaper
        anchors.fill: parent
        visible: root.wallpaperIsVideo && !root.useSafeBlurPipeline
        // source already gates on useSafeBlurPipeline below; layer.enabled
        // is gated to keep the FastBlur shader from being compiled on Niri.
        source: {
            if (!root.wallpaperIsVideo || root.useSafeBlurPipeline || !root._wallpaperSource) return "";
            const path = root._wallpaperSource;
            return path.startsWith("file://") ? path : ("file://" + path);
        }
        fillMode: VideoOutput.PreserveAspectCrop
        loops: MediaPlayer.Infinite
        muted: true
        autoPlay: true

        readonly property bool shouldPlay: root.enableAnimation

        function pauseAndShowFirstFrame() {
            pause()
            seek(0)
        }

        onPlaybackStateChanged: {
            if (playbackState === MediaPlayer.PlayingState && !shouldPlay)
                pauseAndShowFirstFrame()
            if (playbackState === MediaPlayer.StoppedState && visible && shouldPlay)
                play()
        }

        onShouldPlayChanged: {
            if (visible && root.wallpaperIsVideo) {
                if (shouldPlay) play()
                else pauseAndShowFirstFrame()
            }
        }
        
        onVisibleChanged: {
            if (visible && root.wallpaperIsVideo) {
                if (shouldPlay) play()
                else pauseAndShowFirstFrame()
            } else {
                pause()
            }
        }
        
        layer.enabled: root.blurEnabled && !root.useSafeBlurPipeline
        layer.effect: FastBlur {
            radius: root.blurRadius
        }
        
        transform: Scale {
            origin.x: videoWallpaper.width / 2
            origin.y: videoWallpaper.height / 2
            xScale: root.blurEnabled ? root.blurZoom : 1
            yScale: root.blurEnabled ? root.blurZoom : 1
        }
    }

    Video {
        id: videoWallpaperSource
        anchors.fill: parent
        visible: false
        z: -2
        source: {
            if (!root.useSafeBlurPipeline || !root.wallpaperIsVideo || !root._wallpaperSource) return "";
            const path = root._wallpaperSource;
            return path.startsWith("file://") ? path : ("file://" + path);
        }
        fillMode: VideoOutput.PreserveAspectCrop
        loops: MediaPlayer.Infinite
        muted: true
        autoPlay: true

        readonly property bool shouldPlay: root.enableAnimation

        function pauseAndShowFirstFrame() {
            pause()
            seek(0)
        }

        onPlaybackStateChanged: {
            if (playbackState === MediaPlayer.PlayingState && !shouldPlay)
                pauseAndShowFirstFrame()
            if (playbackState === MediaPlayer.StoppedState && root.useSafeBlurPipeline && root.wallpaperIsVideo && shouldPlay)
                play()
        }

        onShouldPlayChanged: {
            if (root.useSafeBlurPipeline && root.wallpaperIsVideo) {
                if (shouldPlay) play()
                else pauseAndShowFirstFrame()
            }
        }
    }

    MultiEffect {
        id: backgroundWallpaperSafe
        anchors.fill: parent
        source: root.wallpaperIsGif ? gifWallpaperSource
              : root.wallpaperIsVideo ? videoWallpaperSource
              : backgroundWallpaperSource
        visible: root.useSafeBlurPipeline
        z: -1

        blurEnabled: root.blurEnabled
        blur: root.blurAmount
        blurMax: root.blurRadius
        saturation: 0.5

        transform: Scale {
            origin.x: backgroundWallpaperSafe.width / 2
            origin.y: backgroundWallpaperSafe.height / 2
            xScale: root.blurEnabled ? root.blurZoom : 1
            yScale: root.blurEnabled ? root.blurZoom : 1
        }
    }
    
    // Gradient overlay for better text readability
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.1) }
            GradientStop { position: 0.5; color: Qt.rgba(0, 0, 0, 0.05) }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.3) }
        }
    }

    // Smoke overlay for login view (dims background)
    Rectangle {
        id: smokeOverlay
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.4)
        opacity: root.showLoginView ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: 350
                easing.type: Easing.OutCubic
            }
        }
    }
    
    // Unlock success overlay (fade to white/black on unlock)
    Rectangle {
        id: unlockOverlay
        anchors.fill: parent
        color: Appearance.colors.colLayer0
        opacity: 0
        z: 100
        
        NumberAnimation {
            id: unlockFadeAnim
            target: unlockOverlay
            property: "opacity"
            from: 0; to: 1
            duration: 300
            easing.type: Easing.InQuad
        }
    }
    
    // Trigger unlock animation before actually unlocking
    Connections {
        target: root.context
        function onUnlocked(action) {
            unlockFadeAnim.start()
        }
    }

    // Wallpaper dim overlay
    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: (Config.options?.lock?.dim?.enable ?? false) ? (Config.options?.lock?.dim?.opacity ?? 0.3) : 0
        z: 0

        Behavior on opacity {
            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
        }
    }

    // ===== CLOCK VIEW (Initial) =====
    Item {
        id: clockView
        anchors.fill: parent
        opacity: root.showLoginView ? 0 : 1
        visible: opacity > 0
        scale: root.showLoginView ? 0.92 : 1
        
        Behavior on opacity {
            NumberAnimation {
                duration: 400
                easing.type: Easing.OutCubic
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: 450
                easing.type: Easing.OutBack
            }
        }
        
        // Config-driven clock properties
        readonly property string clockStyle: Config.options?.lock?.clock?.style ?? "default"
        readonly property string clockPosition: Config.options?.lock?.clock?.position ?? "center"
        readonly property bool statusEnabled: Config.options?.lock?.status?.enable ?? true

        // Status row - compact indicators at top
        Loader {
            active: clockView.statusEnabled
            anchors {
                top: parent.top
                topMargin: 24
                horizontalCenter: parent.horizontalCenter
            }

            sourceComponent: Row {
                spacing: 16

                // WiFi
                Row {
                    spacing: 4
                    visible: Network.wifiEnabled

                    MaterialSymbol {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Network.materialSymbol ?? "signal_wifi_off"
                        iconSize: 16
                        color: Appearance.colors.colOnSurface

                        layer.enabled: Appearance.effectsEnabled
                        layer.effect: DropShadow {
                            horizontalOffset: 0; verticalOffset: 1; radius: 4; samples: 9
                            color: Qt.rgba(0, 0, 0, 0.4)
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Network.networkName ?? ""
                        visible: text.length > 0 && text.length < 16
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.family: Appearance.font.family.main
                        color: Appearance.colors.colOnSurfaceVariant

                        layer.enabled: Appearance.effectsEnabled
                        layer.effect: DropShadow {
                            horizontalOffset: 0; verticalOffset: 1; radius: 4; samples: 9
                            color: Qt.rgba(0, 0, 0, 0.4)
                        }
                    }
                }

                // Bluetooth
                MaterialSymbol {
                    visible: BluetoothStatus.enabled
                    anchors.verticalCenter: parent.verticalCenter
                    text: BluetoothStatus.connected ? "bluetooth_connected" : "bluetooth"
                    iconSize: 16
                    color: Appearance.colors.colOnSurface

                    layer.enabled: Appearance.effectsEnabled
                    layer.effect: DropShadow {
                        horizontalOffset: 0; verticalOffset: 1; radius: 4; samples: 9
                        color: Qt.rgba(0, 0, 0, 0.4)
                    }
                }

                // Volume
                Row {
                    spacing: 4

                    MaterialSymbol {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Audio.value <= 0 ? "volume_off"
                            : Audio.value < 0.33 ? "volume_mute"
                            : Audio.value < 0.66 ? "volume_down"
                            : "volume_up"
                        iconSize: 16
                        color: Appearance.colors.colOnSurface

                        layer.enabled: Appearance.effectsEnabled
                        layer.effect: DropShadow {
                            horizontalOffset: 0; verticalOffset: 1; radius: 4; samples: 9
                            color: Qt.rgba(0, 0, 0, 0.4)
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Math.round(Audio.value * 100) + "%"
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.family: Appearance.font.family.numbers
                        color: Appearance.colors.colOnSurfaceVariant

                        layer.enabled: Appearance.effectsEnabled
                        layer.effect: DropShadow {
                            horizontalOffset: 0; verticalOffset: 1; radius: 4; samples: 9
                            color: Qt.rgba(0, 0, 0, 0.4)
                        }
                    }
                }

                // Battery (laptop only)
                Row {
                    spacing: 4
                    visible: UPower.displayDevice?.isPresent ?? false

                    MaterialSymbol {
                        anchors.verticalCenter: parent.verticalCenter
                        text: {
                            const pct = UPower.displayDevice?.percentage ?? 0
                            const charging = UPower.displayDevice?.state === UPowerDeviceState.Charging
                            if (charging) return "battery_charging_full"
                            if (pct <= 10) return "battery_alert"
                            if (pct <= 30) return "battery_2_bar"
                            if (pct <= 60) return "battery_4_bar"
                            if (pct <= 80) return "battery_5_bar"
                            return "battery_full"
                        }
                        iconSize: 16
                        color: {
                            const pct = UPower.displayDevice?.percentage ?? 0
                            return pct <= 15 ? Appearance.colors.colError : Appearance.colors.colOnSurface
                        }

                        layer.enabled: Appearance.effectsEnabled
                        layer.effect: DropShadow {
                            horizontalOffset: 0; verticalOffset: 1; radius: 4; samples: 9
                            color: Qt.rgba(0, 0, 0, 0.4)
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Math.round(UPower.displayDevice?.percentage ?? 0) + "%"
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.family: Appearance.font.family.numbers
                        color: Appearance.colors.colOnSurfaceVariant

                        layer.enabled: Appearance.effectsEnabled
                        layer.effect: DropShadow {
                            horizontalOffset: 0; verticalOffset: 1; radius: 4; samples: 9
                            color: Qt.rgba(0, 0, 0, 0.4)
                        }
                    }
                }
            }
        }

        // Clock container - position-aware
        Item {
            id: clockContainer
            width: clockContent.implicitWidth
            height: clockContent.implicitHeight

            states: [
                State {
                    name: "center"; when: clockView.clockPosition === "center"
                    AnchorChanges {
                        target: clockContainer
                        anchors.horizontalCenter: clockView.horizontalCenter
                        anchors.verticalCenter: clockView.verticalCenter
                    }
                    PropertyChanges { target: clockContainer; anchors.verticalCenterOffset: -80 }
                },
                State {
                    name: "topLeft"; when: clockView.clockPosition === "topLeft"
                    AnchorChanges {
                        target: clockContainer
                        anchors.left: clockView.left
                        anchors.top: clockView.top
                    }
                    PropertyChanges { target: clockContainer; anchors.leftMargin: 48; anchors.topMargin: 80 }
                },
                State {
                    name: "bottomLeft"; when: clockView.clockPosition === "bottomLeft"
                    AnchorChanges {
                        target: clockContainer
                        anchors.left: clockView.left
                        anchors.bottom: clockView.bottom
                    }
                    PropertyChanges { target: clockContainer; anchors.leftMargin: 48; anchors.bottomMargin: 140 }
                }
            ]

            // Default digital clock
            ColumnLayout {
                id: clockContent
                visible: clockView.clockStyle !== "analog"
                spacing: 4

                Text {
                    id: clockText
                    Layout.alignment: clockView.clockPosition === "center" ? Qt.AlignHCenter : Qt.AlignLeft
                    text: DateTime.time
                    font.pixelSize: Math.round((clockView.clockStyle === "minimal" ? 72 : 112) * Appearance.fontSizeScale)
                    font.weight: Font.Light
                    font.family: Appearance.font.family.numbers
                    color: Appearance.colors.colOnSurface

                    layer.enabled: Appearance.effectsEnabled
                    layer.effect: DropShadow {
                        horizontalOffset: 0
                        verticalOffset: 3
                        radius: 16
                        samples: 33
                        color: Qt.rgba(0, 0, 0, 0.5)
                    }
                }

                Text {
                    id: dateText
                    Layout.alignment: clockView.clockPosition === "center" ? Qt.AlignHCenter : Qt.AlignLeft
                    text: Qt.formatDate(new Date(), "dddd, d MMMM")
                    font.pixelSize: Math.round((clockView.clockStyle === "minimal" ? 15 : 20) * Appearance.fontSizeScale)
                    font.weight: Font.Normal
                    font.family: Appearance.font.family.title
                    font.letterSpacing: 0.5
                    color: Appearance.colors.colOnSurface

                    layer.enabled: Appearance.effectsEnabled
                    layer.effect: DropShadow {
                        horizontalOffset: 0
                        verticalOffset: 1
                        radius: 8
                        samples: 17
                        color: Qt.rgba(0, 0, 0, 0.4)
                    }

                    Timer {
                        interval: 60000
                        running: true
                        repeat: true
                        onTriggered: dateText.text = Qt.formatDate(new Date(), "dddd, d MMMM")
                    }
                }
            }

            // Analog clock - CookieClock from background widgets
            Loader {
                id: analogClockLoader
                active: clockView.clockStyle === "analog"
                anchors.centerIn: parent

                sourceComponent: Item {
                    id: analogRoot
                    width: cookieClock.implicitSize + dateTextAnalog.implicitHeight + 20
                    height: width

                    BackgroundClock.CookieClock {
                        id: cookieClock
                        implicitSize: Math.round(230 * Appearance.fontSizeScale)
                        anchors.horizontalCenter: parent.horizontalCenter
                    }

                    Text {
                        id: dateTextAnalog
                        anchors {
                            horizontalCenter: parent.horizontalCenter
                            top: cookieClock.bottom
                            topMargin: 16
                        }
                        text: Qt.formatDate(new Date(), "dddd, d MMMM")
                        font.pixelSize: Math.round(16 * Appearance.fontSizeScale)
                        font.weight: Font.Normal
                        font.family: Appearance.font.family.title
                        font.letterSpacing: 0.5
                        color: Appearance.colors.colOnSurface

                        layer.enabled: Appearance.effectsEnabled
                        layer.effect: DropShadow {
                            horizontalOffset: 0; verticalOffset: 1; radius: 8; samples: 17
                            color: Qt.rgba(0, 0, 0, 0.4)
                        }

                        Timer {
                            interval: 60000; running: true; repeat: true
                            onTriggered: dateTextAnalog.text = Qt.formatDate(new Date(), "dddd, d MMMM")
                        }
                    }
                }
            }
        }

        // Media player widget (below clock) - only show if music is actually playing or paused
        Loader {
            id: mediaWidgetLoader
            active: MprisController.activePlayer !== null && 
                    MprisController.activePlayer.playbackState !== MprisPlaybackState.Stopped &&
                    (MprisController.activePlayer.trackTitle?.length > 0 ?? false)
            anchors {
                horizontalCenter: parent.horizontalCenter
                top: parent.verticalCenter
                topMargin: 60
            }
            
            sourceComponent: LockMediaWidget {
                player: MprisController.activePlayer
                width: 360
                height: 120
            }
        }

        // Lock screen notifications - grouped by app, read-only
        Loader {
            id: lockNotificationsLoader
            readonly property bool lockNotifEnabled: Config.options?.lock?.notifications?.enable ?? false
            readonly property int lockNotifMaxCount: Config.options?.lock?.notifications?.maxCount ?? 3
            readonly property bool lockNotifShowBody: Config.options?.lock?.notifications?.showBody ?? true
            readonly property string lockNotifPosition: {
                const pos = Config.options?.lock?.notifications?.position ?? "auto"
                return pos === "auto" ? "center" : pos
            }
            active: lockNotifEnabled && Notifications.list.length > 0

            anchors {
                top: mediaWidgetLoader.active ? mediaWidgetLoader.bottom : parent.verticalCenter
                topMargin: mediaWidgetLoader.active ? 16 : 100
                bottom: parent.bottom
                bottomMargin: 80
            }
            width: Math.min(380, parent.width - 80)

            states: [
                State {
                    name: "center"; when: lockNotificationsLoader.lockNotifPosition === "center"
                    AnchorChanges {
                        target: lockNotificationsLoader
                        anchors.horizontalCenter: clockView.horizontalCenter
                    }
                },
                State {
                    name: "left"; when: lockNotificationsLoader.lockNotifPosition === "left"
                    AnchorChanges {
                        target: lockNotificationsLoader
                        anchors.left: clockView.left
                    }
                    PropertyChanges { target: lockNotificationsLoader; anchors.leftMargin: 40 }
                },
                State {
                    name: "right"; when: lockNotificationsLoader.lockNotifPosition === "right"
                    AnchorChanges {
                        target: lockNotificationsLoader
                        anchors.right: clockView.right
                    }
                    PropertyChanges { target: lockNotificationsLoader; anchors.rightMargin: 40 }
                }
            ]

            sourceComponent: Column {
                spacing: 8
                clip: true

                Repeater {
                    model: {
                        const apps = Notifications.appNameList
                        const max = lockNotificationsLoader.lockNotifMaxCount
                        return apps.length > max ? apps.slice(0, max) : apps
                    }

                    delegate: Item {
                        id: groupDelegate
                        required property var modelData
                        readonly property var group: Notifications.groupsByAppName[modelData] ?? null
                        readonly property var latestNotif: group?.notifications?.[0] ?? null
                        readonly property int groupCount: group?.notifications?.length ?? 0
                        property bool expanded: false

                        width: parent.width
                        height: groupCol.implicitHeight
                        visible: latestNotif !== null

                        Column {
                            id: groupCol
                            width: parent.width
                            spacing: 4

                            // Main card — always visible, clickable to expand
                            Rectangle {
                                id: groupCard
                                width: parent.width
                                height: groupContent.implicitHeight + 16
                                radius: Appearance.rounding.normal
                                color: groupMouseArea.containsMouse
                                    ? ColorUtils.transparentize(Appearance.colors.colLayer1, 0.04)
                                    : ColorUtils.transparentize(Appearance.colors.colLayer1, 0.08)

                                Behavior on color { ColorAnimation { duration: Appearance.animation.elementMoveFast.duration } }

                                layer.enabled: Appearance.effectsEnabled
                                layer.effect: DropShadow {
                                    horizontalOffset: 0
                                    verticalOffset: 2
                                    radius: 8
                                    samples: 17
                                    color: Qt.rgba(0, 0, 0, 0.3)
                                }

                                MouseArea {
                                    id: groupMouseArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: groupDelegate.groupCount > 1 ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: {
                                        if (groupDelegate.groupCount > 1) groupDelegate.expanded = !groupDelegate.expanded
                                    }
                                }

                                RowLayout {
                                    id: groupContent
                                    anchors {
                                        left: parent.left; right: parent.right
                                        verticalCenter: parent.verticalCenter
                                        margins: 12
                                    }
                                    spacing: 10

                                    // App icon
                                    Item {
                                        Layout.alignment: Qt.AlignTop
                                        Layout.preferredWidth: 32
                                        Layout.preferredHeight: 32

                                        NotificationAppIcon {
                                            anchors.fill: parent
                                            appIcon: groupDelegate.latestNotif?.appIcon ?? ""
                                            image: root.safeLockNotificationImage(groupDelegate.latestNotif?.image)
                                            summary: groupDelegate.latestNotif?.summary ?? ""
                                            urgency: groupDelegate.latestNotif?.urgency ?? 0
                                        }

                                        // Count badge
                                        Rectangle {
                                            visible: groupDelegate.groupCount > 1
                                            anchors {
                                                right: parent.right
                                                top: parent.top
                                                rightMargin: -4
                                                topMargin: -4
                                            }
                                            width: Math.max(16, badgeText.implicitWidth + 6)
                                            height: 16
                                            radius: Appearance.rounding.full
                                            color: Appearance.colors.colPrimary
                                            z: 1

                                            Text {
                                                id: badgeText
                                                anchors.centerIn: parent
                                                text: groupDelegate.groupCount
                                                font.pixelSize: 9
                                                font.weight: Font.Bold
                                                font.family: Appearance.font.family.numbers
                                                color: Appearance.colors.colOnPrimary
                                            }
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2

                                        RowLayout {
                                            Layout.fillWidth: true
                                            // App name
                                            Text {
                                                Layout.fillWidth: true
                                                text: groupDelegate.modelData ?? ""
                                                font.pixelSize: Appearance.font.pixelSize.smaller
                                                font.weight: Font.Medium
                                                font.family: Appearance.font.family.main
                                                color: Appearance.colors.colOnSurfaceVariant
                                                elide: Text.ElideRight
                                                visible: text.length > 0
                                            }

                                            // Expand indicator
                                            MaterialSymbol {
                                                visible: groupDelegate.groupCount > 1
                                                text: groupDelegate.expanded ? "expand_less" : "expand_more"
                                                iconSize: 14
                                                color: Appearance.colors.colOnSurfaceVariant
                                            }
                                        }

                                        // Latest notification summary
                                        Text {
                                            Layout.fillWidth: true
                                            text: groupDelegate.latestNotif?.summary ?? ""
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            font.weight: Font.Medium
                                            font.family: Appearance.font.family.main
                                            color: Appearance.colors.colOnSurface
                                            elide: Text.ElideRight
                                            maximumLineCount: 1
                                        }

                                        // Body (optional)
                                        Text {
                                            Layout.fillWidth: true
                                            visible: lockNotificationsLoader.lockNotifShowBody && text.length > 0
                                            text: groupDelegate.latestNotif?.body ?? ""
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                            font.family: Appearance.font.family.main
                                            color: Appearance.colors.colOnSurfaceVariant
                                            elide: Text.ElideRight
                                            maximumLineCount: 2
                                            wrapMode: Text.WordWrap
                                        }
                                    }
                                }
                            }

                            // Expanded notifications
                            Column {
                                id: expandedCol
                                width: parent.width - 16
                                anchors.horizontalCenter: parent.horizontalCenter
                                spacing: 3
                                visible: groupDelegate.expanded
                                clip: true

                                Repeater {
                                    model: groupDelegate.expanded ? (groupDelegate.group?.notifications?.slice(1) ?? []) : []

                                    delegate: Rectangle {
                                        id: expandedCard
                                        required property var modelData
                                        width: parent.width
                                        height: expandedContent.implicitHeight + 10
                                        radius: Appearance.rounding.small
                                        color: ColorUtils.transparentize(Appearance.colors.colLayer1, 0.12)

                                        RowLayout {
                                            id: expandedContent
                                            anchors {
                                                left: parent.left; right: parent.right
                                                verticalCenter: parent.verticalCenter
                                                margins: 8
                                            }
                                            spacing: 8

                                            NotificationAppIcon {
                                                Layout.alignment: Qt.AlignTop
                                                Layout.preferredWidth: 22
                                                Layout.preferredHeight: 22
                                                appIcon: expandedCard.modelData?.appIcon ?? ""
                                                image: root.safeLockNotificationImage(expandedCard.modelData?.image)
                                                summary: expandedCard.modelData?.summary ?? ""
                                                urgency: expandedCard.modelData?.urgency ?? 0
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 1

                                                Text {
                                                    Layout.fillWidth: true
                                                    text: expandedCard.modelData?.summary ?? ""
                                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                                    font.weight: Font.Medium
                                                    font.family: Appearance.font.family.main
                                                    color: Appearance.colors.colOnSurface
                                                    elide: Text.ElideRight
                                                    maximumLineCount: 1
                                                }

                                                Text {
                                                    Layout.fillWidth: true
                                                    visible: lockNotificationsLoader.lockNotifShowBody && text.length > 0
                                                    text: expandedCard.modelData?.body ?? ""
                                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                                    font.family: Appearance.font.family.main
                                                    color: Appearance.colors.colOnSurfaceVariant
                                                    elide: Text.ElideRight
                                                    maximumLineCount: 2
                                                    wrapMode: Text.WordWrap
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Overflow indicator for remaining app groups
                Text {
                    visible: Notifications.appNameList.length > lockNotificationsLoader.lockNotifMaxCount
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "+" + (Notifications.appNameList.length - lockNotificationsLoader.lockNotifMaxCount) + " " + Translation.tr("more")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.family: Appearance.font.family.main
                    color: Appearance.colors.colOnSurfaceVariant

                    layer.enabled: Appearance.effectsEnabled
                    layer.effect: DropShadow {
                        horizontalOffset: 0
                        verticalOffset: 1
                        radius: 4
                        samples: 9
                        color: Qt.rgba(0, 0, 0, 0.3)
                    }
                }
            }
        }
        
        // Bottom left: Weather widget
        Loader {
            active: Weather.data?.temp && Weather.data.temp.length > 0
            visible: active
            anchors {
                left: parent.left
                bottom: parent.bottom
                leftMargin: 40
                bottomMargin: 40
            }
            
            sourceComponent: Row {
                spacing: 12
                
                function isNightTime(): bool {
                    const now = new Date()
                    const currentHour = now.getHours()
                    const currentMinutes = now.getMinutes()
                    const currentTime = currentHour * 60 + currentMinutes
                    
                    function parseTime(timeStr: string): int {
                        if (!timeStr) return -1
                        const match = timeStr.match(/(\d+):(\d+)\s*(AM|PM)/i)
                        if (!match) return -1
                        let hours = parseInt(match[1])
                        const minutes = parseInt(match[2])
                        const isPM = match[3].toUpperCase() === "PM"
                        if (isPM && hours !== 12) hours += 12
                        if (!isPM && hours === 12) hours = 0
                        return hours * 60 + minutes
                    }
                    
                    const sunrise = parseTime(Weather.data?.sunrise ?? "")
                    const sunset = parseTime(Weather.data?.sunset ?? "")
                    
                    if (sunrise < 0 || sunset < 0) return currentHour < 6 || currentHour >= 20
                    return currentTime < sunrise || currentTime >= sunset
                }
                
                function getWeatherIconWithTime(code: string): string {
                    return Icons.getWeatherIcon(code, Weather.isNightNow()) ?? "cloud"
                }
                
                MaterialSymbol {
                    anchors.verticalCenter: parent.verticalCenter
                    text: parent.getWeatherIconWithTime(Weather.data?.wCode ?? "113")
                    iconSize: 44
                    fill: 0
                    color: Appearance.colors.colOnSurface
                    
                    layer.enabled: Appearance.effectsEnabled
                    layer.effect: DropShadow {
                        horizontalOffset: 0
                        verticalOffset: 2
                        radius: 8
                        samples: 17
                        color: Qt.rgba(0, 0, 0, 0.4)
                    }
                }
                
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    
                    Text {
                        text: Weather.data?.temp ?? ""
                        font.pixelSize: Math.round(26 * Appearance.fontSizeScale)
                        font.weight: Font.Light
                        font.family: Appearance.font.family.main
                        color: Appearance.colors.colOnSurface
                        
                        layer.enabled: Appearance.effectsEnabled
                        layer.effect: DropShadow {
                            horizontalOffset: 0
                            verticalOffset: 1
                            radius: 4
                            samples: 9
                            color: Qt.rgba(0, 0, 0, 0.4)
                        }
                    }
                    
                    Text {
                        text: Weather.visibleCity
                        visible: Weather.showVisibleCity
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.family: Appearance.font.family.main
                        color: Appearance.colors.colOnSurfaceVariant
                        
                        layer.enabled: Appearance.effectsEnabled
                        layer.effect: DropShadow {
                            horizontalOffset: 0
                            verticalOffset: 1
                            radius: 2
                            samples: 5
                            color: Qt.rgba(0, 0, 0, 0.3)
                        }
                    }
                }
            }
        }

        // Bottom hint text
        Text {
            id: hintText
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 40
            anchors.horizontalCenter: parent.horizontalCenter
            text: Translation.tr("Press any key or click to unlock")
            font.pixelSize: Appearance.font.pixelSize.normal
            font.family: Appearance.font.family.main
            color: Appearance.colors.colOnSurfaceVariant
            opacity: hintOpacity
            
            property real hintOpacity: 0.7
            
            layer.enabled: Appearance.effectsEnabled
            layer.effect: DropShadow {
                horizontalOffset: 0
                verticalOffset: 1
                radius: 4
                samples: 9
                color: Qt.rgba(0, 0, 0, 0.3)
            }
            
            Timer {
                id: hintFadeTimer
                interval: 4000
                running: clockView.visible
                onTriggered: hintText.hintOpacity = 0
            }
            
            // Reset hint when returning to clock view
            Connections {
                target: clockView
                function onVisibleChanged() {
                    if (clockView.visible) {
                        hintText.hintOpacity = 0.7
                        hintFadeTimer.restart()
                    }
                }
            }
            
            Behavior on hintOpacity {
                NumberAnimation {
                    duration: Appearance.animation.elementMove.duration * 2
                    easing.type: Easing.OutCubic
                }
            }
        }
    }

    // ===== LOGIN VIEW =====
    Item {
        id: loginView
        anchors.fill: parent
        opacity: root.showLoginView ? 1 : 0
        visible: opacity > 0
        
        Behavior on opacity {
            NumberAnimation {
                duration: 400
                easing.type: Easing.OutCubic
            }
        }

        // Centered login content with staggered animation
        ColumnLayout {
            id: loginContent
            anchors.centerIn: parent
            spacing: 16
            
            // Animation properties for stagger effect
            property real animProgress: root.showLoginView ? 1 : 0
            Behavior on animProgress {
                NumberAnimation {
                    duration: 500
                    easing.type: Easing.OutCubic
                }
            }
            
            // User Avatar - Material You style (large circular with accent ring)
            Item {
                id: avatarContainer
                Layout.alignment: Qt.AlignHCenter
                width: 100
                height: 100
                
                // Stagger animation
                opacity: Math.min(1, loginContent.animProgress * 3)
                scale: 0.8 + (0.2 * Math.min(1, loginContent.animProgress * 3))
                transformOrigin: Item.Center
                
                Behavior on scale {
                    NumberAnimation { duration: 350; easing.type: Easing.OutBack }
                }
                
                // Accent ring behind avatar
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width + 8
                    height: parent.height + 8
                    radius: width / 2
                    color: "transparent"
                    border.color: Appearance.colors.colPrimary
                    border.width: 3
                    opacity: 0.8
                    
                    layer.enabled: Appearance.effectsEnabled
                    layer.effect: DropShadow {
                        horizontalOffset: 0
                        verticalOffset: 4
                        radius: 16
                        samples: 33
                        color: Qt.rgba(0, 0, 0, 0.4)
                    }
                }
                
                // Avatar circle
                Rectangle {
                    id: avatarCircle
                    anchors.fill: parent
                    radius: width / 2
                    color: Appearance.colors.colPrimary
                    clip: true
                    
                    Image {
                        id: avatarImage
                        anchors.fill: parent
                        source: lockAvatarResolver.resolvedSource
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: true
                        smooth: true
                        mipmap: true
                        sourceSize.width: avatarCircle.width * 2
                        sourceSize.height: avatarCircle.height * 2
                        visible: status === Image.Ready
                        
                        layer.enabled: Appearance.effectsEnabled
                        layer.effect: OpacityMask {
                            maskSource: Rectangle {
                                width: avatarCircle.width
                                height: avatarCircle.height
                                radius: width / 2
                            }
                        }
                    }

                    QtObject {
                        id: lockAvatarResolver
                        property int avatarIndex: 0
                        readonly property string resolvedSource: Directories.avatarSourceAt(avatarIndex)
                        readonly property string primaryWatch: Directories.userAvatarSourcePrimary
                        onPrimaryWatchChanged: avatarIndex = 0
                        readonly property int imgStatus: avatarImage.status
                        onImgStatusChanged: {
                            if (imgStatus === Image.Error) {
                                const nextIdx = avatarIndex + 1
                                if (nextIdx < Directories.userAvatarPaths.length)
                                    avatarIndex = nextIdx
                            }
                        }
                    }
                    
                    // Fallback initial
                    Text {
                        anchors.centerIn: parent
                        text: (SystemInfo.displayName || SystemInfo.username || "?").charAt(0).toUpperCase()
                        font.pixelSize: Math.round(40 * Appearance.fontSizeScale)
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnPrimary
                        visible: avatarImage.status !== Image.Ready
                    }
                }
            }
            
            // Display name
            Text {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 8
                text: SystemInfo.displayName || SystemInfo.username
                font.pixelSize: Math.round(22 * Appearance.fontSizeScale)
                font.weight: Font.Medium
                font.family: Appearance.font.family.main
                color: Appearance.colors.colOnSurface
                
                // Stagger animation (delayed)
                opacity: Math.min(1, Math.max(0, loginContent.animProgress * 3 - 0.3))
                transform: Translate { y: (1 - Math.min(1, Math.max(0, loginContent.animProgress * 3 - 0.3))) * 15 }
                
                layer.enabled: Appearance.effectsEnabled
                layer.effect: DropShadow {
                    horizontalOffset: 0
                    verticalOffset: 1
                    radius: 6
                    samples: 13
                    color: Qt.rgba(0, 0, 0, 0.4)
                }
            }

            // Password field - Material You style pill
            Rectangle {
                id: passwordContainer
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 12
                width: 300
                height: 52
                radius: height / 2
                color: ColorUtils.transparentize(Appearance.colors.colLayer1, 0.2)
                border.color: loginPasswordField.activeFocus 
                    ? Appearance.colors.colPrimary 
                    : ColorUtils.transparentize(Appearance.colors.colOnSurface, 0.7)
                border.width: loginPasswordField.activeFocus ? 2 : 1
                
                // Stagger animation (more delayed)
                opacity: Math.min(1, Math.max(0, loginContent.animProgress * 3 - 0.5))
                
                // Combined transform for stagger Y + shake X
                property real staggerY: (1 - Math.min(1, Math.max(0, loginContent.animProgress * 3 - 0.5))) * 20
                property real shakeOffset: 0
                transform: Translate { x: passwordContainer.shakeOffset; y: passwordContainer.staggerY }
                
                Behavior on border.color {
                    animation: ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
                }
                
                layer.enabled: Appearance.effectsEnabled
                layer.effect: DropShadow {
                    horizontalOffset: 0
                    verticalOffset: 4
                    radius: 12
                    samples: 25
                    color: Qt.rgba(0, 0, 0, 0.3)
                }
                
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 20
                    anchors.rightMargin: 8
                    spacing: 8
                    
                    // Fingerprint icon (if available)
                    Loader {
                        Layout.alignment: Qt.AlignVCenter
                        active: root.context.fingerprintsConfigured
                        visible: active
                        
                        sourceComponent: MaterialSymbol {
                            text: "fingerprint"
                            iconSize: 22
                            fill: 1
                            color: Appearance.colors.colOnSurfaceVariant
                        }
                    }
                    
                    TextInput {
                        id: loginPasswordField
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        verticalAlignment: Text.AlignVCenter
                        
                        echoMode: TextInput.Password
                        inputMethodHints: Qt.ImhSensitiveData
                        font.pixelSize: Appearance.font.pixelSize.large
                        font.family: Appearance.font.family.main
                        color: materialShapeChars ? "transparent" : Appearance.colors.colOnSurface
                        selectionColor: Appearance.colors.colPrimary
                        selectedTextColor: Appearance.colors.colOnPrimary
                        
                        enabled: !root.context.unlockInProgress
                        
                        property bool materialShapeChars: Config.options?.lock?.materialShapeChars ?? false
                        property string placeholder: GlobalStates.screenUnlockFailed 
                            ? Translation.tr("Incorrect password") 
                            : Translation.tr("Password")
                        
                        Text {
                            anchors.fill: parent
                            verticalAlignment: Text.AlignVCenter
                            text: loginPasswordField.placeholder
                            font: loginPasswordField.font
                            color: GlobalStates.screenUnlockFailed 
                                ? Appearance.colors.colError 
                                : Appearance.colors.colOnSurfaceVariant
                            visible: loginPasswordField.text.length === 0
                        }
                        
                        onTextChanged: root.context.currentText = text
                        onAccepted: {
                            root.hasAttemptedUnlock = true
                            root.context.tryUnlock(root.ctrlHeld)
                        }
                        
                        Connections {
                            target: root.context
                            function onCurrentTextChanged() {
                                loginPasswordField.text = root.context.currentText
                            }
                        }
                        
                        Keys.onPressed: event => {
                            root.context.resetClearTimer()
                        }
                        
                        // Material shape password chars overlay
                        Loader {
                            active: loginPasswordField.materialShapeChars && loginPasswordField.text.length > 0
                            anchors {
                                fill: parent
                                leftMargin: 4
                                rightMargin: 4
                            }
                            sourceComponent: PasswordChars {
                                length: root.context.currentText.length
                            }
                        }
                    }
                    
                    // Submit button
                    Rectangle {
                        id: submitButton
                        Layout.preferredWidth: 36
                        Layout.preferredHeight: 36
                        Layout.alignment: Qt.AlignVCenter
                        radius: width / 2
                        color: submitMouseArea.pressed 
                            ? Appearance.colors.colPrimaryActive 
                            : submitMouseArea.containsMouse 
                                ? Appearance.colors.colPrimaryHover 
                                : Appearance.colors.colPrimary
                        
                        Behavior on color {
                            animation: ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
                        }
                        
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: {
                                if (root.context.targetAction === LockContext.ActionEnum.Unlock) {
                                    return root.ctrlHeld ? "emoji_food_beverage" : "arrow_forward"
                                } else if (root.context.targetAction === LockContext.ActionEnum.Poweroff) {
                                    return "power_settings_new"
                                } else if (root.context.targetAction === LockContext.ActionEnum.Reboot) {
                                    return "restart_alt"
                                }
                            }
                            iconSize: 20
                            color: Appearance.colors.colOnPrimary
                        }
                        
                        MouseArea {
                            id: submitMouseArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            enabled: !root.context.unlockInProgress
                            onClicked: {
                                root.hasAttemptedUnlock = true
                                root.context.tryUnlock(root.ctrlHeld)
                            }
                        }
                    }
                }
                
                // Shake animation
                SequentialAnimation {
                    id: wrongPasswordShakeAnim
                    NumberAnimation { target: passwordContainer; property: "shakeOffset"; to: -20; duration: 50 }
                    NumberAnimation { target: passwordContainer; property: "shakeOffset"; to: 20; duration: 50 }
                    NumberAnimation { target: passwordContainer; property: "shakeOffset"; to: -10; duration: 40 }
                    NumberAnimation { target: passwordContainer; property: "shakeOffset"; to: 10; duration: 40 }
                    NumberAnimation { target: passwordContainer; property: "shakeOffset"; to: 0; duration: 30 }
                }
                
                Connections {
                    target: GlobalStates
                    function onScreenUnlockFailedChanged() {
                        if (GlobalStates.screenUnlockFailed && root.hasAttemptedUnlock) {
                            wrongPasswordShakeAnim.restart()
                        }
                    }
                }
            }

            // Loading indicator
            Loader {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 8
                active: root.context.unlockInProgress
                visible: active
                
                sourceComponent: StyledIndeterminateProgressBar {
                    width: 120
                }
            }
            
            // Fingerprint hint
            Loader {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 8
                active: root.context.fingerprintsConfigured && !root.context.unlockInProgress
                visible: active
                
                sourceComponent: Text {
                    text: Translation.tr("Touch sensor to unlock")
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.family: Appearance.font.family.main
                    color: Appearance.colors.colOnSurfaceVariant
                    
                    layer.enabled: Appearance.effectsEnabled
                    layer.effect: DropShadow {
                        horizontalOffset: 0
                        verticalOffset: 1
                        radius: 2
                        samples: 5
                        color: Qt.rgba(0, 0, 0, 0.3)
                    }
                }
            }
        }
        
        // Bottom right: Power options
        Row {
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            anchors.bottomMargin: 24
            anchors.rightMargin: 24
            spacing: 8
            
            LockIconButton {
                icon: "dark_mode"
                tooltip: Translation.tr("Sleep")
                onClicked: Session.suspend()
            }
            
            LockIconButton {
                icon: "power_settings_new"
                tooltip: Translation.tr("Shut down")
                toggled: root.context.targetAction === LockContext.ActionEnum.Poweroff
                onClicked: {
                    if (!root.requirePasswordToPower) {
                        root.context.unlocked(LockContext.ActionEnum.Poweroff)
                        return
                    }
                    if (root.context.targetAction === LockContext.ActionEnum.Poweroff) {
                        root.context.resetTargetAction()
                    } else {
                        root.context.targetAction = LockContext.ActionEnum.Poweroff
                        loginPasswordField.forceActiveFocus()
                    }
                }
            }
            
            LockIconButton {
                icon: "restart_alt"
                tooltip: Translation.tr("Restart")
                toggled: root.context.targetAction === LockContext.ActionEnum.Reboot
                onClicked: {
                    if (!root.requirePasswordToPower) {
                        root.context.unlocked(LockContext.ActionEnum.Reboot)
                        return
                    }
                    if (root.context.targetAction === LockContext.ActionEnum.Reboot) {
                        root.context.resetTargetAction()
                    } else {
                        root.context.targetAction = LockContext.ActionEnum.Reboot
                        loginPasswordField.forceActiveFocus()
                    }
                }
            }
        }
        
        // Bottom left: Battery & keyboard layout
        Row {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.bottomMargin: 24
            anchors.leftMargin: 24
            spacing: 16
            
            // Battery
            Loader {
                active: UPower.displayDevice.isLaptopBattery
                visible: active
                anchors.verticalCenter: parent.verticalCenter
                
                sourceComponent: Row {
                    spacing: 6
                    
                    MaterialSymbol {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Battery.isCharging ? "bolt" : "battery_full"
                        iconSize: 20
                        fill: 1
                        color: (Battery.isLow && !Battery.isCharging) 
                            ? Appearance.colors.colError 
                            : Appearance.colors.colOnSurfaceVariant
                        
                        layer.enabled: Appearance.effectsEnabled
                        layer.effect: DropShadow {
                            horizontalOffset: 0
                            verticalOffset: 1
                            radius: 3
                            samples: 7
                            color: Qt.rgba(0, 0, 0, 0.3)
                        }
                    }
                    
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Math.round(Battery.percentage * 100) + "%"
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.family: Appearance.font.family.main
                        color: (Battery.isLow && !Battery.isCharging) 
                            ? Appearance.colors.colError 
                            : Appearance.colors.colOnSurfaceVariant
                        
                        layer.enabled: Appearance.effectsEnabled
                        layer.effect: DropShadow {
                            horizontalOffset: 0
                            verticalOffset: 1
                            radius: 3
                            samples: 7
                            color: Qt.rgba(0, 0, 0, 0.3)
                        }
                    }
                }
            }
            
            // Keyboard layout
            Loader {
                active: typeof HyprlandXkb !== "undefined" && HyprlandXkb.currentLayoutCode.length > 0
                visible: active
                anchors.verticalCenter: parent.verticalCenter
                
                sourceComponent: Row {
                    spacing: 4
                    
                    MaterialSymbol {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "keyboard"
                        iconSize: 18
                        fill: 1
                        color: Appearance.colors.colOnSurfaceVariant
                        
                        layer.enabled: Appearance.effectsEnabled
                        layer.effect: DropShadow {
                            horizontalOffset: 0
                            verticalOffset: 1
                            radius: 2
                            samples: 5
                            color: Qt.rgba(0, 0, 0, 0.3)
                        }
                    }
                    
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: HyprlandXkb.currentLayoutCode.toUpperCase()
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.family: Appearance.font.family.main
                        color: Appearance.colors.colOnSurfaceVariant
                        
                        layer.enabled: Appearance.effectsEnabled
                        layer.effect: DropShadow {
                            horizontalOffset: 0
                            verticalOffset: 1
                            radius: 2
                            samples: 5
                            color: Qt.rgba(0, 0, 0, 0.3)
                        }
                    }
                }
            }
            
            // On-screen keyboard toggle
            LockIconButton {
                icon: "keyboard"
                tooltip: Translation.tr("Virtual keyboard")
                toggled: root.oskVisible
                anchors.verticalCenter: parent.verticalCenter
                onClicked: root.oskVisible = !root.oskVisible
            }
        }
    }

    // ===== SCREENSAVER =====

    // List image files from wallpaper folder for screensaver cycling
    FolderListModel {
        id: screensaverWallpaperModel
        folder: "file://" + Directories.wallpapersPath
        nameFilters: ["*.png", "*.jpg", "*.jpeg", "*.webp", "*.bmp"]
        showDirs: false
        sortField: FolderListModel.Unsorted
    }

    // Idle timer — triggers screensaver after no interaction
    Timer {
        id: screensaverIdleTimer
        interval: root.screensaverIdleSeconds * 1000
        running: root.screensaverEnabled && GlobalStates.screenLocked && !root.screensaverActive && root.currentView === "clock"
        repeat: false
        onTriggered: {
            if (screensaverWallpaperModel.count > 0) {
                screensaverState.loadFirst()
                root.screensaverActive = true
            }
        }
    }

    // Wallpaper cycling timer
    Timer {
        id: screensaverCycleTimer
        interval: root.screensaverWallpaperInterval * 1000
        running: root.screensaverActive
        repeat: true
        onTriggered: screensaverState.startNextTransition()
    }

    // Screensaver state management
    QtObject {
        id: screensaverState
        // Which layer is currently the visible "front" (true = A is front)
        property bool aIsFront: true
        // Pending source to load into the back layer before crossfading
        property string pendingSource: ""
        // Track what's currently showing so we avoid repeats
        property string visiblePath: ""

        function pickRandomPath(): string {
            if (screensaverWallpaperModel.count === 0) return ""
            let idx = Math.floor(Math.random() * screensaverWallpaperModel.count)
            let path = screensaverWallpaperModel.get(idx, "filePath")
            if (path === visiblePath && screensaverWallpaperModel.count > 1) {
                idx = (idx + 1) % screensaverWallpaperModel.count
                path = screensaverWallpaperModel.get(idx, "filePath")
            }
            return path
        }

        function loadFirst() {
            const path = pickRandomPath()
            if (!path) return
            visiblePath = path
            // Load directly into front layer, no crossfade
            ssWallpaperA.source = path
            ssWallpaperA.opacity = 1
            ssWallpaperB.source = ""
            ssWallpaperB.opacity = 0
            aIsFront = true
        }

        function startNextTransition() {
            const path = pickRandomPath()
            if (!path) return
            pendingSource = path
            // Load into the back (hidden) layer
            const backImg = aIsFront ? ssWallpaperB : ssWallpaperA
            backImg.source = path
            // If already cached/loaded, statusChanged won't fire — check immediately
            if (backImg.status === Image.Ready) {
                commitCrossfade()
            }
            // Otherwise onStatusChanged in the Image handles it
        }

        function commitCrossfade() {
            if (!pendingSource) return
            visiblePath = pendingSource
            pendingSource = ""
            // Crossfade: fade in the back layer on top; keep front at opacity 1
            const incoming = aIsFront ? ssWallpaperB : ssWallpaperA
            incoming.opacity = 0
            ssCrossfadeAnim.target = incoming
            ssCrossfadeAnim.start()
            aIsFront = !aIsFront
        }

        function reset() {
            pendingSource = ""
            visiblePath = ""
            ssCrossfadeAnim.stop()
            ssWallpaperA.source = ""
            ssWallpaperB.source = ""
            ssWallpaperA.opacity = 1
            ssWallpaperB.opacity = 0
            aIsFront = true
        }
    }

    // Timer to clear the old (now hidden) layer source after crossfade finishes
    Timer {
        id: ssClearOldTimer
        interval: 1800  // slightly longer than crossfade duration
        onTriggered: {
            // Clear the hidden layer to free memory
            if (screensaverState.aIsFront) {
                ssWallpaperB.source = ""
            } else {
                ssWallpaperA.source = ""
            }
            gc()
        }
    }

    // Screensaver overlay with crossfading wallpapers
    Item {
        id: screensaverOverlay
        anchors.fill: parent
        z: 50
        visible: opacity > 0
        opacity: root.screensaverActive ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: 800
                easing.type: Easing.InOutQuad
            }
        }

        // Layer A
        Image {
            id: ssWallpaperA
            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: false
            opacity: 1

            onStatusChanged: {
                if (status === Image.Ready && !screensaverState.aIsFront && screensaverState.pendingSource) {
                    screensaverState.commitCrossfade()
                }
            }
        }

        // Layer B
        Image {
            id: ssWallpaperB
            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: false
            opacity: 0

            onStatusChanged: {
                if (status === Image.Ready && screensaverState.aIsFront && screensaverState.pendingSource) {
                    screensaverState.commitCrossfade()
                }
            }
        }

        // Crossfade animation — only fades IN the incoming layer; outgoing stays opaque until done
        NumberAnimation {
            id: ssCrossfadeAnim
            property: "opacity"
            duration: 1500
            easing.type: Easing.InOutQuad
            from: 0; to: 1
            onFinished: {
                // Snap the now-hidden old layer to 0
                if (screensaverState.aIsFront) {
                    ssWallpaperB.opacity = 0
                } else {
                    ssWallpaperA.opacity = 0
                }
                ssClearOldTimer.restart()
            }
        }

        // Subtle gradient overlay for readability
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.15) }
                GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.35) }
            }
        }

        // DVD-style bouncing clock — reuses lockscreen clock style + audio visualizer
        Item {
            id: driftingClock
            visible: root.screensaverShowClock
            width: driftClockCol.implicitWidth + 40
            height: driftClockCol.implicitHeight + 20

            property real vx: 1.5
            property real vy: 1.0
            property color dvdColor: Appearance.colors.colOnSurface

            readonly property var dvdColors: [
                "#FF6B6B", "#51CF66", "#339AF0", "#FCC419",
                "#CC5DE8", "#FF922B", "#22B8CF", "#FF8787",
                "#69DB7C", "#748FFC", "#F06595", "#20C997"
            ]
            property int dvdColorIndex: 0

            function cycleColor() {
                dvdColorIndex = (dvdColorIndex + 1) % dvdColors.length
                dvdColor = dvdColors[dvdColorIndex]
            }

            Behavior on dvdColor {
                ColorAnimation { duration: 300; easing.type: Easing.OutCubic }
            }

            Component.onCompleted: {
                x = Math.random() * Math.max(1, screensaverOverlay.width - width)
                y = Math.random() * Math.max(1, screensaverOverlay.height - height)
                vx = (Math.random() < 0.5 ? -1 : 1) * (1.8 + Math.random() * 0.8)
                vy = (Math.random() < 0.5 ? -1 : 1) * (1.2 + Math.random() * 0.6)
            }

            FrameAnimation {
                running: root.screensaverActive && driftingClock.visible
                onTriggered: {
                    const dt = frameTime * 60
                    let nx = driftingClock.x + driftingClock.vx * dt
                    let ny = driftingClock.y + driftingClock.vy * dt
                    const maxX = screensaverOverlay.width - driftingClock.width
                    const maxY = screensaverOverlay.height - driftingClock.height
                    let bounced = false

                    if (maxX > 0) {
                        if (nx <= 0) { nx = 0; driftingClock.vx = Math.abs(driftingClock.vx); bounced = true }
                        else if (nx >= maxX) { nx = maxX; driftingClock.vx = -Math.abs(driftingClock.vx); bounced = true }
                    }
                    if (maxY > 0) {
                        if (ny <= 0) { ny = 0; driftingClock.vy = Math.abs(driftingClock.vy); bounced = true }
                        else if (ny >= maxY) { ny = maxY; driftingClock.vy = -Math.abs(driftingClock.vy); bounced = true }
                    }

                    if (bounced) driftingClock.cycleColor()

                    driftingClock.x = nx
                    driftingClock.y = ny
                }
            }

            // Screensaver media state
            readonly property var ssPlayer: MprisController.activePlayer
            readonly property bool ssHasPlayer: ssPlayer !== null &&
                ssPlayer.playbackState !== MprisPlaybackState.Stopped &&
                (ssPlayer.trackTitle?.length > 0 ?? false)

            property string ssArtFileName: ssPlayer?.trackArtUrl ? Qt.md5(ssPlayer.trackArtUrl) : ""
            property string ssArtFilePath: ssArtFileName ? `${Directories.coverArt}/${ssArtFileName}` : ""
            property bool ssArtDownloaded: false
            property string ssDisplayedArt: ssArtDownloaded ? Qt.resolvedUrl(ssArtFilePath) : ""
            property int _ssDownloadRetryCount: 0

            function ssCheckArt() {
                if (!ssPlayer?.trackArtUrl) { ssArtDownloaded = false; _ssDownloadRetryCount = 0; return }
                ssArtExistsChecker.running = true
            }

            onSsArtFilePathChanged: { _ssDownloadRetryCount = 0; ssCheckArt() }
            Connections {
                target: driftingClock.ssPlayer
                function onTrackArtUrlChanged() { driftingClock._ssDownloadRetryCount = 0; driftingClock.ssCheckArt() }
            }

            Process {
                id: ssArtExistsChecker
                command: ["/usr/bin/test", "-f", driftingClock.ssArtFilePath]
                onExited: (exitCode, exitStatus) => {
                    if (exitCode === 0) { driftingClock.ssArtDownloaded = true; driftingClock._ssDownloadRetryCount = 0 }
                    else { driftingClock.ssArtDownloaded = false; ssArtDownloader.targetFile = driftingClock.ssPlayer?.trackArtUrl ?? ""; ssArtDownloader.artFilePath = driftingClock.ssArtFilePath; ssArtDownloader.running = true }
                }
            }

            Process {
                id: ssArtDownloader
                property string targetFile
                property string artFilePath
                command: ["/usr/bin/bash", "-c", `
                    if [ -f '${artFilePath}' ]; then exit 0; fi
                    mkdir -p '${Directories.coverArt}'
                    tmp='${artFilePath}.tmp'
                    /usr/bin/curl -sSL --connect-timeout 10 --max-time 30 '${targetFile}' -o "$tmp" && \
                    [ -s "$tmp" ] && /usr/bin/mv -f "$tmp" '${artFilePath}' || { rm -f "$tmp"; exit 1; }
                `]
                onExited: (exitCode) => {
                    if (exitCode === 0) { driftingClock.ssArtDownloaded = true; driftingClock._ssDownloadRetryCount = 0 }
                    else { driftingClock.ssArtDownloaded = false; if (driftingClock._ssDownloadRetryCount < 3 && driftingClock.ssPlayer?.trackArtUrl) { driftingClock._ssDownloadRetryCount++; ssRetryTimer.start() } }
                }
            }

            Timer {
                id: ssRetryTimer
                interval: 1000 * driftingClock._ssDownloadRetryCount
                repeat: false
                onTriggered: { if (driftingClock.ssPlayer?.trackArtUrl && !driftingClock.ssArtDownloaded) { ssArtDownloader.targetFile = driftingClock.ssPlayer.trackArtUrl; ssArtDownloader.artFilePath = driftingClock.ssArtFilePath; ssArtDownloader.running = true } }
            }

            ColorQuantizer {
                id: ssColorQuantizer
                source: driftingClock.ssDisplayedArt
                depth: 0
                rescaleSize: 1
            }

            property color ssArtDominantColor: ColorUtils.mix(
                ssColorQuantizer?.colors[0] ?? Appearance.colors.colPrimary,
                Appearance.colors.colPrimaryContainer, 0.7
            )
            property QtObject ssBlendedColors: AdaptedMaterialScheme { color: driftingClock.ssArtDominantColor }

            readonly property color ssColText: Appearance.inir.colText
            readonly property color ssColTextSecondary: Appearance.inir.colTextSecondary
            readonly property color ssColPrimary: Appearance.inir.colPrimary
            readonly property color ssColLayer1: Appearance.inir.colLayer1
            readonly property color ssColLayer2: Appearance.inir.colLayer2

            CavaProcess {
                id: ssCavaProcess
                active: root.screensaverActive && driftingClock.visible &&
                        driftingClock.ssHasPlayer &&
                        (driftingClock.ssPlayer?.isPlaying ?? false) &&
                        Appearance.effectsEnabled
            }

            ColumnLayout {
                id: driftClockCol
                anchors.centerIn: parent
                spacing: 8

                // Time — same style as lockscreen clock
                Text {
                    id: ssClock
                    Layout.alignment: Qt.AlignHCenter
                    text: Qt.formatTime(new Date(), "hh:mm")
                    font.pixelSize: Math.round(108 * Appearance.fontSizeScale)
                    font.weight: Font.DemiBold
                    font.family: Appearance.font.family.appearance
                    color: driftingClock.dvdColor

                    Behavior on color {
                        ColorAnimation { duration: 300; easing.type: Easing.OutCubic }
                    }

                    layer.enabled: Appearance.effectsEnabled
                    layer.effect: DropShadow {
                        horizontalOffset: 0
                        verticalOffset: 3
                        radius: 16
                        samples: 33
                        color: Qt.rgba(0, 0, 0, 0.5)
                    }

                    Timer {
                        interval: 1000
                        running: root.screensaverActive
                        repeat: true
                        onTriggered: ssClock.text = Qt.formatTime(new Date(), "hh:mm")
                    }
                }

                // Date — same style as lockscreen date
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: Qt.formatDate(new Date(), "dddd, d MMMM")
                    font.pixelSize: Math.round(22 * Appearance.fontSizeScale)
                    font.weight: Font.Normal
                    font.family: Appearance.font.family.main
                    color: driftingClock.dvdColor

                    Behavior on color {
                        ColorAnimation { duration: 300; easing.type: Easing.OutCubic }
                    }

                    layer.enabled: Appearance.effectsEnabled
                    layer.effect: DropShadow {
                        horizontalOffset: 0
                        verticalOffset: 1
                        radius: 8
                        samples: 17
                        color: Qt.rgba(0, 0, 0, 0.4)
                    }
                }

                // Media player card (no controls) — shown when music is playing
                Loader {
                    id: ssMediaLoader
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 12
                    active: driftingClock.ssHasPlayer
                    visible: active

                    sourceComponent: Rectangle {
                        id: ssCard
                        width: 360
                        implicitHeight: 130
                        radius: Appearance.angelEverywhere ? Appearance.angel.roundingNormal
                            : Appearance.inirEverywhere ? Appearance.inir.roundingNormal : Appearance.rounding.normal
                        color: Appearance.angelEverywhere ? Appearance.angel.colGlassCard
                             : Appearance.inirEverywhere ? Appearance.inir.colLayer1
                             : Appearance.auroraEverywhere ? ColorUtils.transparentize(driftingClock.ssBlendedColors?.colLayer0 ?? Appearance.colors.colLayer0, 0.7)
                             : (driftingClock.ssBlendedColors?.colLayer0 ?? Appearance.colors.colLayer0)
                        border.width: Appearance.angelEverywhere ? Appearance.angel.cardBorderWidth
                            : Appearance.inirEverywhere ? 1 : 0
                        border.color: Appearance.angelEverywhere ? Appearance.angel.colCardBorder
                            : Appearance.inirEverywhere ? Appearance.inir.colBorder : "transparent"
                        clip: true

                        layer.enabled: Appearance.effectsEnabled
                        layer.effect: OpacityMask {
                            maskSource: Rectangle { width: ssCard.width; height: ssCard.height; radius: ssCard.radius }
                        }

                        // Cover art background
                        Image {
                            anchors.fill: parent
                            source: driftingClock.ssDisplayedArt
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            opacity: Appearance.inirEverywhere ? 0.2 : (Appearance.auroraEverywhere ? 0.3 : 0.6)
                            visible: driftingClock.ssDisplayedArt !== ""

                            layer.enabled: Appearance.effectsEnabled
                            layer.effect: MultiEffect {
                                blurEnabled: true
                                blur: Appearance.inirEverywhere ? 0.5 : 0.4
                                blurMax: 32
                                saturation: Appearance.inirEverywhere ? 0.1 : 0.4
                            }
                        }

                        // Dark overlay
                        Rectangle {
                            anchors.fill: parent
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: ColorUtils.transparentize(driftingClock.ssBlendedColors?.colLayer0 ?? Appearance.colors.colLayer0, 0.7) }
                                GradientStop { position: 0.3; color: ColorUtils.transparentize(driftingClock.ssBlendedColors?.colLayer0 ?? Appearance.colors.colLayer0, 0.4) }
                                GradientStop { position: 1.0; color: ColorUtils.transparentize(driftingClock.ssBlendedColors?.colLayer0 ?? Appearance.colors.colLayer0, 0.2) }
                            }
                        }

                        // Visualizer at bottom
                        WaveVisualizer {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: 30
                            live: driftingClock.ssPlayer?.isPlaying ?? false
                            points: ssCavaProcess.points
                            maxVisualizerValue: 1000
                            smoothing: 2
                            color: ColorUtils.transparentize(
                                Appearance.inirEverywhere ? driftingClock.ssColPrimary : (driftingClock.ssBlendedColors?.colPrimary ?? Appearance.colors.colPrimary),
                                0.6
                            )
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 10

                            // Cover art thumbnail
                            Rectangle {
                                id: ssCoverArtContainer
                                Layout.preferredWidth: 110
                                Layout.preferredHeight: 110
                                Layout.alignment: Qt.AlignVCenter
                                radius: Appearance.inirEverywhere ? Appearance.inir.roundingSmall : Appearance.rounding.small
                                color: "transparent"
                                clip: true

                                layer.enabled: Appearance.effectsEnabled
                                layer.effect: OpacityMask {
                                    maskSource: Rectangle {
                                        width: 110; height: 110
                                        radius: Appearance.inirEverywhere ? Appearance.inir.roundingSmall : Appearance.rounding.small
                                    }
                                }

                                Image {
                                    id: ssCoverArt
                                    anchors.fill: parent
                                    source: driftingClock.ssDisplayedArt
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                }

                                Rectangle {
                                    anchors.fill: parent
                                    color: Appearance.inirEverywhere ? driftingClock.ssColLayer2 : (driftingClock.ssBlendedColors?.colLayer1 ?? Appearance.colors.colLayer1)
                                    visible: !driftingClock.ssArtDownloaded

                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "music_note"
                                        iconSize: 32
                                        color: Appearance.inirEverywhere ? driftingClock.ssColTextSecondary : (driftingClock.ssBlendedColors?.colSubtext ?? Appearance.colors.colSubtext)
                                    }
                                }
                            }

                            // Info column
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                spacing: 2

                                // Title
                                StyledText {
                                    Layout.fillWidth: true
                                    text: StringUtils.cleanMusicTitle(driftingClock.ssPlayer?.trackTitle) || "\u2014"
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    font.weight: Font.Medium
                                    color: Appearance.inirEverywhere ? driftingClock.ssColText : (driftingClock.ssBlendedColors?.colOnLayer0 ?? Appearance.colors.colOnLayer0)
                                    elide: Text.ElideRight
                                }

                                // Artist
                                StyledText {
                                    Layout.fillWidth: true
                                    text: driftingClock.ssPlayer?.trackArtist || ""
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.inirEverywhere ? driftingClock.ssColTextSecondary : (driftingClock.ssBlendedColors?.colSubtext ?? Appearance.colors.colSubtext)
                                    elide: Text.ElideRight
                                    visible: text !== ""
                                }

                                Item { Layout.fillHeight: true }

                                // Progress bar
                                Item {
                                    Layout.fillWidth: true
                                    implicitHeight: 16

                                    Loader {
                                        anchors.fill: parent
                                        active: driftingClock.ssPlayer?.canSeek ?? false
                                        sourceComponent: StyledSlider {
                                            configuration: StyledSlider.Configuration.Wavy
                                            wavy: driftingClock.ssPlayer?.isPlaying ?? false
                                            animateWave: driftingClock.ssPlayer?.isPlaying ?? false
                                            highlightColor: Appearance.inirEverywhere ? driftingClock.ssColPrimary : (driftingClock.ssBlendedColors?.colPrimary ?? Appearance.colors.colPrimary)
                                            trackColor: Appearance.inirEverywhere ? Appearance.inir.colLayer2 : (driftingClock.ssBlendedColors?.colSecondaryContainer ?? Appearance.colors.colSecondaryContainer)
                                            handleColor: Appearance.inirEverywhere ? driftingClock.ssColPrimary : (driftingClock.ssBlendedColors?.colPrimary ?? Appearance.colors.colPrimary)
                                            value: driftingClock.ssPlayer?.length > 0 ? driftingClock.ssPlayer.position / driftingClock.ssPlayer.length : 0
                                            scrollable: false
                                        }
                                    }

                                    Loader {
                                        anchors.fill: parent
                                        active: !(driftingClock.ssPlayer?.canSeek ?? false)
                                        sourceComponent: StyledProgressBar {
                                            wavy: driftingClock.ssPlayer?.isPlaying ?? false
                                            animateWave: driftingClock.ssPlayer?.isPlaying ?? false
                                            highlightColor: Appearance.inirEverywhere ? driftingClock.ssColPrimary : (driftingClock.ssBlendedColors?.colPrimary ?? Appearance.colors.colPrimary)
                                            trackColor: Appearance.inirEverywhere ? Appearance.inir.colLayer2 : (driftingClock.ssBlendedColors?.colSecondaryContainer ?? Appearance.colors.colSecondaryContainer)
                                            value: driftingClock.ssPlayer?.length > 0 ? driftingClock.ssPlayer.position / driftingClock.ssPlayer.length : 0
                                        }
                                    }
                                }

                                // Time row
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 4

                                    StyledText {
                                        text: StringUtils.friendlyTimeForSeconds(driftingClock.ssPlayer?.position ?? 0)
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        font.family: Appearance.font.family.numbers
                                        color: Appearance.inirEverywhere ? driftingClock.ssColText : (driftingClock.ssBlendedColors?.colOnLayer0 ?? Appearance.colors.colOnLayer0)
                                    }

                                    Item { Layout.fillWidth: true }

                                    StyledText {
                                        text: StringUtils.friendlyTimeForSeconds(driftingClock.ssPlayer?.length ?? 0)
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        font.family: Appearance.font.family.numbers
                                        color: Appearance.inirEverywhere ? driftingClock.ssColText : (driftingClock.ssBlendedColors?.colOnLayer0 ?? Appearance.colors.colOnLayer0)
                                    }
                                }
                            }
                        }
                    }
                }

                // Position update timer for screensaver media
                Timer {
                    running: driftingClock.ssPlayer?.playbackState === MprisPlaybackState.Playing
                    interval: 1000
                    repeat: true
                    onTriggered: driftingClock.ssPlayer?.positionChanged()
                }
            }
        }
    }

    // Exit screensaver on any interaction (resets idle timer too)
    function resetScreensaver(): void {
        if (root.screensaverActive) {
            root.screensaverActive = false
            screensaverState.reset()
        }
        screensaverIdleTimer.restart()
    }
    // On-screen keyboard
    LockKeyboard {
        id: lockKeyboard
        visible: root.oskVisible
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 80
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(parent.width * 0.6, 640)

        onKeyClicked: key => {
            loginPasswordField.text += key
            loginPasswordField.forceActiveFocus()
        }
        onBackspaceClicked: {
            if (loginPasswordField.text.length > 0) {
                loginPasswordField.text = loginPasswordField.text.slice(0, -1)
            }
            loginPasswordField.forceActiveFocus()
        }
        onEnterClicked: {
            if (root.context.currentText.length > 0) {
                root.hasAttemptedUnlock = true
                root.context.tryUnlock(root.ctrlHeld)
            }
        }
        onCloseRequested: root.oskVisible = false
    }

    // ===== INPUT HANDLING =====
    
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton
    focus: true
    activeFocusOnTab: true
    
    onClicked: mouse => {
        if (root.screensaverActive) {
            root.resetScreensaver()
            return
        }
        if (!root.showLoginView) {
            root.switchToLogin()
        } else {
            root.forceFieldFocus()
        }
    }

    onPositionChanged: mouse => {
        root.resetScreensaver()
        if (root.showLoginView) {
            root.forceFieldFocus()
        }
    }
    
    property bool ctrlHeld: false
    
    function forceFieldFocus(): void {
        if (root.showLoginView && loginView.visible) {
            loginPasswordField.forceActiveFocus()
        }
    }
    
    function switchToLogin(): void {
        root.currentView = "login"
        // Use Qt.callLater to ensure loginView is visible before focusing
        Qt.callLater(() => loginPasswordField.forceActiveFocus())
    }
    
    Connections {
        target: context
        function onShouldReFocus() {
            forceFieldFocus()
        }
    }
    
    Keys.onPressed: event => {
        root.context.resetClearTimer()
        root.resetScreensaver()

        if (event.key === Qt.Key_Control) {
            root.ctrlHeld = true
            return
        }
        
        if (event.key === Qt.Key_Escape) {
            if (root.context.currentText.length > 0) {
                root.context.currentText = ""
            } else if (root.showLoginView && root.currentView === "login") {
                root.currentView = "clock"
            }
            return
        }
        
        // Switch to login view on any key press
        if (!root.showLoginView) {
            root.currentView = "login"
            // Capture printable character and add to password field
            const inputChar = event.text
            Qt.callLater(() => {
                loginPasswordField.forceActiveFocus()
                if (inputChar.length === 1 && inputChar.charCodeAt(0) >= 32) {
                    loginPasswordField.text += inputChar
                }
            })
            return
        }
        
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (root.context.currentText.length > 0) {
                root.hasAttemptedUnlock = true
                root.context.tryUnlock(root.ctrlHeld)
            }
            event.accepted = true
            return
        }
        
        // Ensure field has focus
        if (!loginPasswordField.activeFocus) {
            loginPasswordField.forceActiveFocus()
        }
    }
    
    Keys.onReleased: event => {
        if (event.key === Qt.Key_Control) {
            root.ctrlHeld = false
        }
        forceFieldFocus()
    }
    
    Component.onCompleted: {
        // Start in clock view, will switch to login on interaction
        root.currentView = "clock"
        GlobalStates.screenUnlockFailed = false
        root.hasAttemptedUnlock = false
        // Force focus to receive keyboard events - use callLater to ensure component is fully ready
        Qt.callLater(() => root.forceActiveFocus())
    }
    
    // Reset state when lock screen is activated
    Connections {
        target: GlobalStates
        function onScreenLockedChanged() {
            if (GlobalStates.screenLocked) {
                root.currentView = "clock"
                root.hasAttemptedUnlock = false
                root.screensaverActive = false
                screensaverState.reset()
                GlobalStates.screenUnlockFailed = false
                // Force focus when lock activates - delayed to ensure visibility
                Qt.callLater(() => root.forceActiveFocus())
            }
        }
    }
    
    // Ensure focus on first show (workaround for focus issues with Loader)
    Timer {
        id: focusEnsureTimer
        interval: 100
        running: GlobalStates.screenLocked && root.visible
        repeat: true
        property int attempts: 0
        onTriggered: {
            attempts++
            if (attempts > 30) {  // Stop after 3 seconds
                repeat = false
                return
            }
            if (!root.activeFocus && !loginPasswordField.activeFocus) {
                root.forceActiveFocus()
            } else {
                // Focus acquired, stop retrying
                repeat = false
            }
        }
        onRunningChanged: {
            if (running) attempts = 0
        }
    }
    
    // ===== COMPONENTS =====
    
    component LockIconButton: Rectangle {
        id: lockBtn
        required property string icon
        property string tooltip: ""
        property bool toggled: false
        
        signal clicked()
        
        width: 44
        height: 44
        radius: Appearance.rounding.normal
        color: {
            if (toggled) return Appearance.colors.colPrimary
            if (lockBtnMouse.pressed) return ColorUtils.transparentize(Appearance.colors.colOnSurface, 0.7)
            if (lockBtnMouse.containsMouse) return ColorUtils.transparentize(Appearance.colors.colOnSurface, 0.85)
            return ColorUtils.transparentize(Appearance.colors.colLayer1, 0.3)
        }
        
        Behavior on color {
            animation: ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
        }
        
        layer.enabled: Appearance.effectsEnabled
        layer.effect: DropShadow {
            horizontalOffset: 0
            verticalOffset: 2
            radius: 8
            samples: 17
            color: Qt.rgba(0, 0, 0, 0.3)
        }
        
        MaterialSymbol {
            anchors.centerIn: parent
            text: lockBtn.icon
            iconSize: 22
            color: lockBtn.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurface
        }
        
        MouseArea {
            id: lockBtnMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: lockBtn.clicked()
        }
        
        StyledToolTip {
            visible: lockBtnMouse.containsMouse && lockBtn.tooltip.length > 0
            text: lockBtn.tooltip
        }
    }
}
