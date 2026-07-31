import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.services

AndroidQuickToggleButton {
    id: root

    name: Translation.tr("Privacy mode")
    statusText: PrivacyMode.active ? Translation.tr("Active") : ""
    toggled: PrivacyMode.active
    buttonIcon: "privacy_tip"

    mainAction: () => {
        PrivacyMode.toggle()
    }

    StyledToolTip {
        text: PrivacyMode.active
            ? Translation.tr("Privacy mode") + " (" + Translation.tr("active") + ")"
            : Translation.tr("Privacy mode")
    }
}
