import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.waffle.looks
import qs.modules.waffle.bar
import Quickshell
import Quickshell.Hyprland

Button {
    id: root

    required property var toplevel
    property real previewWidthConstraint: Looks.dp(200)
    property real previewHeightConstraint: Looks.dp(110)
    padding: Looks.dp(5)
    Layout.fillHeight: true

    // Window id for WindowPreviewService: Niri numeric id or Hyprland address
    readonly property var previewWindowId: {
        if (!root.toplevel) return -1
        if (CompositorService.isHyprland) {
            const addr = root.toplevel.HyprlandToplevel?.address
            return addr ? ("0x" + addr) : -1
        }
        if (root.toplevel.niriWindowId)
            return root.toplevel.niriWindowId
        const match = NiriService.findNiriWindow(root.toplevel)
        return match?.niriWindow?.id ?? -1
    }

    onClicked: {
        if (CompositorService.isNiri && root.previewWindowId > 0) {
            NiriService.focusWindow(root.previewWindowId)
        } else {
            root.toplevel?.activate()
        }
    }

    background: Rectangle {
        id: background
        radius: Looks.radius.medium
        color: root.down ? Looks.colors.bg2Active : (root.hovered ? Looks.colors.bg2Hover : ColorUtils.transparentize(Looks.colors.bg2))
        Behavior on color {
            animation: ColorAnimation { duration: Looks.transition.enabled ? Looks.transition.duration.ultraFast : 0; easing.type: Easing.BezierSpline; easing.bezierCurve: Looks.transition.easing.bezierCurve.standard }
        }
    }

    contentItem: ColumnLayout {
        id: contentItem
        anchors.fill: parent
        anchors.margins: root.padding
        spacing: 5

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Looks.dp(8)

            WAppIcon {
                id: appIcon
                Layout.leftMargin: Looks.radius.large - root.padding + Looks.dp(2)
                Layout.alignment: Qt.AlignVCenter
                iconName: root.toplevel ? AppSearch.guessIcon(root.toplevel.appId) : ""
                implicitSize: Looks.dp(16)
            }

            Item {
                id: appTitleContainer
                Layout.fillWidth: true
                Layout.fillHeight: true
                implicitHeight: closeButton.implicitHeight
                WText {
                    id: appTitleText
                    anchors.fill: parent
                    text: root.toplevel?.title ?? ""
                    elide: Text.ElideRight
                    font.pixelSize: Looks.font.pixelSize.large
                    font.weight: Looks.font.weight.thin
                    color: Looks.colors.fg1
                }
            }

            WindowCloseButton {
                id: closeButton
            }
        }

        Loader {
            id: previewLoader
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: Looks.radius.large - root.padding
            Layout.topMargin: 0

            sourceComponent: Item {
                id: previewContainer
                implicitWidth: root.previewWidthConstraint
                implicitHeight: root.previewHeightConstraint

                // Fallback icon when preview not available
                WAppIcon {
                    anchors.centerIn: parent
                    visible: !previewImage.hasPreview
                    iconName: root.toplevel ? AppSearch.guessIcon(root.toplevel.appId) : ""
                    implicitSize: Looks.dp(64)
                    opacity: 0.5
                }

                // Window preview using WindowPreviewService (Niri + Hyprland)
                Image {
                    id: previewImage
                    anchors.fill: parent
                    property string previewUrl: ""
                    property bool hasPreview: status === Image.Ready

                    source: previewUrl
                    asynchronous: true
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    mipmap: true
                    visible: hasPreview
                    opacity: hasPreview ? 1 : 0

                    Behavior on opacity {
                        NumberAnimation {
                            duration: Looks.transition.enabled
                                ? Looks.transition.duration.normal : 0
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Looks.transition.easing.bezierCurve.standard
                        }
                    }

                    // Listen for preview updates from WindowPreviewService
                    Connections {
                        target: WindowPreviewService
                        function onPreviewUpdated(updatedId): void {
                            if (updatedId === root.previewWindowId) {
                                previewImage.previewUrl = WindowPreviewService.getPreviewUrl(updatedId)
                            }
                        }
                        function onCaptureComplete(): void {
                            if (root.previewWindowId !== -1) {
                                const url = WindowPreviewService.getPreviewUrl(root.previewWindowId)
                                if (url) previewImage.previewUrl = url
                            }
                        }
                    }

                    Component.onCompleted: {
                        WindowPreviewService.initialize()
                        if (root.previewWindowId !== -1) {
                            Qt.callLater(() => {
                                const url = WindowPreviewService.getPreviewUrl(root.previewWindowId)
                                if (url) previewImage.previewUrl = url
                            })
                        }
                    }
                }

                // Rounded corners mask
                layer.enabled: previewImage.hasPreview
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: previewContainer.width
                        height: previewContainer.height
                        radius: Looks.radius.medium
                    }
                }
            }
        }
    }

    component WindowCloseButton: CloseButton {
        visible: root.hovered
        Layout.leftMargin: Looks.dp(4)
        radius: Looks.radius.large - root.padding
        onClicked: {
            if (CompositorService.isNiri && root.previewWindowId > 0) {
                NiriService.closeWindow(root.previewWindowId)
            } else {
                root.toplevel?.close()
            }
        }
    }
}
