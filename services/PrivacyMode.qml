pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.modules.common
import qs.services

/**
 * PrivacyMode - manual toggle for screen sharing/streaming.
 * While active: masks the weather location, WiFi network name, lock screen
 * avatar/name, and notification body text, and forces Do Not Disturb on.
 * DND is restored to whatever it was before Privacy Mode was enabled.
 */
Singleton {
    id: root

    readonly property bool active: Persistent.states.privacyMode.active

    property bool _prevSilent: false

    function enable(): void {
        if (root.active) return
        root._prevSilent = Notifications.silent
        Notifications.silent = true
        Persistent.states.privacyMode.active = true
    }

    function disable(): void {
        if (!root.active) return
        Persistent.states.privacyMode.active = false
        Notifications.silent = root._prevSilent
    }

    function toggle(): void {
        if (root.active) root.disable()
        else root.enable()
    }
}
