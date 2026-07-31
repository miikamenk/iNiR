import QtQuick
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

QuickToggleModel {
    name: Translation.tr("Internet")
    statusText: Network.networkNameForDisplay
    tooltipText: Translation.tr("%1 | Right-click to configure").arg(Network.networkNameForDisplay)
    icon: Network.materialSymbol

    toggled: Network.wifiStatus !== "disabled"
    mainAction: () => Network.toggleWifi()
    hasMenu: true
    altAction: () => {
        AppLauncher.launchNetworkSettings(Network.ethernet)
    }
}
