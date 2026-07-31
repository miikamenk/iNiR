import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.services

QuickToggleButton {
    id: root
    buttonIcon: "privacy_tip"
    toggled: PrivacyMode.active

    onClicked: {
        PrivacyMode.toggle()
    }

    StyledToolTip {
        text: PrivacyMode.active
            ? Translation.tr("Privacy mode") + " (" + Translation.tr("active") + ")"
            : Translation.tr("Privacy mode")
    }
}
