import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.sidebarLeft.anime
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io

Item {
    id: root
    property real padding: 4

    property var inputField: tagInputField
    readonly property var responses: Wallhaven.responses
    property string previewDownloadPath: Directories.booruPreviews
    readonly property string customDownloadFolder: Persistent.states?.wallhaven?.downloadFolder ?? ""
    property string downloadPath: customDownloadFolder.length > 0 ? customDownloadFolder : Directories.booruDownloads
    property string nsfwPath: customDownloadFolder.length > 0 ? customDownloadFolder : Directories.booruDownloadsNsfw
    property bool showFilters: false
    readonly property bool hasApiKey: (Config.options?.sidebar?.wallhaven?.apiKey ?? "").length > 0
    property string commandPrefix: "/"
    property real scrollOnNewResponse: 100

    property bool pullLoading: false
    property int pullLoadingGap: 80
    property real normalizedPullDistance: Math.max(0, (1 - Math.exp(-wallhavenResponseListView.verticalOvershoot / 50)) * wallhavenResponseListView.dragging)

    Connections {
        target: Wallhaven
        function onResponseFinished() {
            pullLoading = false
        }
    }

    property var allCommands: [
        {
            name: "clear",
            description: Translation.tr("Clear the current list of images"),
            execute: () => {
                Wallhaven.clearResponses();
            }
        },
        {
            name: "next",
            description: Translation.tr("Get the next page of results"),
            execute: () => {
                if (root.responses.length > 0) {
                    const lastResponse = root.responses[root.responses.length - 1];
                    root.handleInput(`${lastResponse.tags.join(" ")} ${parseInt(lastResponse.page) + 1}`);
                } else {
                    root.handleInput("");
                }
            }
        },
        {
            name: "safe",
            description: Translation.tr("Disable NSFW content"),
            execute: () => {
                Persistent.states.booru.allowNsfw = false;
            }
        },
        {
            name: "lewd",
            description: Translation.tr("Allow NSFW content (requires Wallhaven API key)"),
            execute: () => {
                Persistent.states.booru.allowNsfw = true;
            }
        }
    ]

    function handleInput(inputText) {
        if (inputText.startsWith(root.commandPrefix)) {
            const command = inputText.split(" ")[0].substring(1);
            const args = inputText.split(" ").slice(1);
            const commandObj = root.allCommands.find(cmd => cmd.name === `${command}`);
            if (commandObj) {
                commandObj.execute(args);
            } else {
                Wallhaven.addSystemMessage(Translation.tr("Unknown command: ") + command);
            }
        }
        else if (inputText.trim() == "+") {
            root.handleInput(`${root.commandPrefix}next`);
        }
        else {
            const tagList = inputText.split(/\s+/).filter(tag => tag.length > 0);
            let pageIndex = 1;
            for (let i = 0; i < tagList.length; ++i) {
                if (/^\d+$/.test(tagList[i])) {
                    pageIndex = parseInt(tagList[i], 10);
                    tagList.splice(i, 1);
                    break;
                }
            }
            Wallhaven.makeRequest(tagList, Persistent.states.booru.allowNsfw, Config.options?.sidebar?.wallhaven?.limit ?? 24, pageIndex);
        }
    }

    onFocusChanged: (focus) => {
        if (focus) {
            tagInputField.forceActiveFocus()
        }
    }

    property real pageKeyScrollAmount: wallhavenResponseListView.height / 2
    Keys.onPressed: (event) => {
        tagInputField.forceActiveFocus()
        if (event.modifiers === Qt.NoModifier) {
            if (event.key === Qt.Key_PageUp) {
                if (wallhavenResponseListView.atYBeginning) return;
                wallhavenResponseListView.contentY = Math.max(0, wallhavenResponseListView.contentY - root.pageKeyScrollAmount)
                event.accepted = true
            } else if (event.key === Qt.Key_PageDown) {
                if (wallhavenResponseListView.atYEnd) return;
                wallhavenResponseListView.contentY = Math.min(wallhavenResponseListView.contentHeight, wallhavenResponseListView.contentY + root.pageKeyScrollAmount)
                event.accepted = true
            }
        }
    }

    ColumnLayout {
        id: columnLayout
        anchors {
            fill: parent
            margins: root.padding
        }
        spacing: root.padding

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: swipeView.width
                    height: swipeView.height
                    radius: Appearance.rounding.small
                }
            }

            ScrollEdgeFade {
                z: 1
                target: wallhavenResponseListView
                vertical: true
            }

            StyledListView {
                id: wallhavenResponseListView
                z: 0
                anchors.fill: parent
                spacing: 10

                touchpadScrollFactor: (Config.options?.interactions?.scrolling?.touchpadScrollFactor ?? 0.5) * 1.4
                mouseScrollFactor: (Config.options?.interactions?.scrolling?.mouseScrollFactor ?? 1.0) * 1.4

                property int lastResponseLength: 0
                property bool userIsScrolling: false
                
                onMovingChanged: {
                    if (moving) userIsScrolling = true
                    else Qt.callLater(() => { userIsScrolling = false })
                }
                
                onDraggingChanged: {
                    if (dragging) userIsScrolling = true
                    else Qt.callLater(() => { userIsScrolling = false })
                }
                
                Connections {
                    target: root
                    function onResponsesChanged() {
                        const nextLength = root.responses.length
                        if (nextLength === 0) {
                            wallhavenResponseListView.lastResponseLength = 0
                            return
                        }

                        // Once the bounded list is full, a new page rotates the
                        // oldest response without changing the model length.
                        if (nextLength >= wallhavenResponseListView.lastResponseLength
                                && !wallhavenResponseListView.userIsScrolling
                                && wallhavenResponseListView.lastResponseLength > 0) {
                            wallhavenResponseListView.contentY += root.scrollOnNewResponse
                        }
                        wallhavenResponseListView.lastResponseLength = nextLength
                    }
                }

                model: ScriptModel {
                    values: root.responses
                }
                delegate: BooruResponse {
                    responseData: modelData
                    tagInputField: root.inputField
                    previewDownloadPath: root.previewDownloadPath
                    downloadPath: root.downloadPath
                    nsfwPath: root.nsfwPath
                }

                onDragEnded: {
                    const gap = wallhavenResponseListView.verticalOvershoot
                    if (gap > root.pullLoadingGap) {
                        root.pullLoading = true
                        root.handleInput(`${root.commandPrefix}next`)
                    }
                }
            }

            MaterialPlaceholderMessage {
                id: placeholderItem
                anchors.fill: parent
                z: 2
                shown: root.responses.length === 0
                icon: "image"
                text: Translation.tr("Wallhaven wallpapers")
                explanation: Translation.tr("Type tags and hit Enter to search on wallhaven.cc")
                shape: MaterialShape.Shape.Bun
            }

            ScrollToBottomButton {
                z: 3
                target: wallhavenResponseListView
            }

            MaterialLoadingIndicator {
                id: loadingIndicator
                z: 4
                anchors {
                    horizontalCenter: parent.horizontalCenter
                    bottom: parent.bottom
                    bottomMargin: 20 + (root.pullLoading ? 0 : Math.max(0, (root.normalizedPullDistance - 0.5) * 50))
                    Behavior on bottomMargin {
                        enabled: Appearance.animationsEnabled
                        NumberAnimation {
                            duration: Appearance.animation.elementMoveFast.duration
                            easing.type: Appearance.animation.elementMoveFast.type
                            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                        }
                    }
                }
                loading: root.pullLoading || Wallhaven.runningRequests > 0
                pullProgress: Math.min(1, wallhavenResponseListView.verticalOvershoot / root.pullLoadingGap * wallhavenResponseListView.dragging)
                scale: root.pullLoading ? 1 : Math.min(1, root.normalizedPullDistance * 2)
            }
        }

        // ── Wallhaven filter panel ───────────────────────────────────────
        Revealer {
            id: filterRevealer
            vertical: true
            reveal: root.showFilters
            Layout.fillWidth: true

            Rectangle {
                id: filterPanel
                anchors.left: parent.left
                anchors.right: parent.right
                radius: Appearance.rounding.normal - root.padding
                color: Appearance.angelEverywhere ? Appearance.angel.colGlassCard
                    : Appearance.inirEverywhere ? Appearance.inir.colLayer2
                    : Appearance.auroraEverywhere ? Appearance.aurora.colElevatedSurface
                    : Appearance.colors.colLayer2
                implicitHeight: filterColumn.implicitHeight + 16

                ColumnLayout {
                    id: filterColumn
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        margins: 8
                    }
                    spacing: 6

                    FilterSectionLabel { text: Translation.tr("Categories") }
                    Flow {
                        Layout.fillWidth: true
                        spacing: 4
                        FilterChip {
                            chipText: Translation.tr("General")
                            toggled: Persistent.states.wallhaven.catGeneral
                            downAction: () => Persistent.states.wallhaven.catGeneral = !Persistent.states.wallhaven.catGeneral
                        }
                        FilterChip {
                            chipText: Translation.tr("Anime")
                            toggled: Persistent.states.wallhaven.catAnime
                            downAction: () => Persistent.states.wallhaven.catAnime = !Persistent.states.wallhaven.catAnime
                        }
                        FilterChip {
                            chipText: Translation.tr("People")
                            toggled: Persistent.states.wallhaven.catPeople
                            downAction: () => Persistent.states.wallhaven.catPeople = !Persistent.states.wallhaven.catPeople
                        }
                    }

                    FilterSectionLabel { text: Translation.tr("Purity") }
                    Flow {
                        Layout.fillWidth: true
                        spacing: 4
                        FilterChip {
                            chipText: Translation.tr("SFW")
                            toggled: Persistent.states.wallhaven.puritySfw
                            downAction: () => Persistent.states.wallhaven.puritySfw = !Persistent.states.wallhaven.puritySfw
                        }
                        FilterChip {
                            chipText: Translation.tr("Sketchy")
                            toggled: Persistent.states.wallhaven.puritySketchy
                            downAction: () => Persistent.states.wallhaven.puritySketchy = !Persistent.states.wallhaven.puritySketchy
                        }
                        FilterChip {
                            chipText: Translation.tr("NSFW")
                            enabled: root.hasApiKey
                            toggled: Persistent.states.booru.allowNsfw && root.hasApiKey
                            downAction: () => Persistent.states.booru.allowNsfw = !Persistent.states.booru.allowNsfw
                            StyledToolTip {
                                text: root.hasApiKey ? Translation.tr("Include NSFW results")
                                    : Translation.tr("Requires a Wallhaven API key (set in config)")
                            }
                        }
                    }

                    FilterSectionLabel { text: Translation.tr("Sorting") }
                    Flow {
                        Layout.fillWidth: true
                        spacing: 4
                        Repeater {
                            model: [
                                { value: "date_added", label: Translation.tr("Latest") },
                                { value: "relevance", label: Translation.tr("Relevance") },
                                { value: "random", label: Translation.tr("Random") },
                                { value: "views", label: Translation.tr("Views") },
                                { value: "favorites", label: Translation.tr("Favorites") },
                                { value: "toplist", label: Translation.tr("Toplist") },
                                { value: "hot", label: Translation.tr("Hot") },
                            ]
                            delegate: FilterChip {
                                required property var modelData
                                chipText: modelData.label
                                toggled: (Persistent.states.wallhaven.sorting ?? "date_added") === modelData.value
                                downAction: () => Persistent.states.wallhaven.sorting = modelData.value
                            }
                        }
                    }

                    FilterSectionLabel {
                        visible: Persistent.states.wallhaven.sorting === "toplist"
                        text: Translation.tr("Toplist range")
                    }
                    Flow {
                        Layout.fillWidth: true
                        spacing: 4
                        visible: Persistent.states.wallhaven.sorting === "toplist"
                        Repeater {
                            model: ["1d", "3d", "1w", "1M", "3M", "6M", "1y"]
                            delegate: FilterChip {
                                required property string modelData
                                chipText: modelData
                                toggled: (Persistent.states.wallhaven.topRange ?? "1M") === modelData
                                downAction: () => Persistent.states.wallhaven.topRange = modelData
                            }
                        }
                    }

                    FilterSectionLabel { text: Translation.tr("Order") }
                    Flow {
                        Layout.fillWidth: true
                        spacing: 4
                        FilterChip {
                            chipText: Translation.tr("Descending")
                            toggled: (Persistent.states.wallhaven.order ?? "desc") !== "asc"
                            downAction: () => Persistent.states.wallhaven.order = "desc"
                        }
                        FilterChip {
                            chipText: Translation.tr("Ascending")
                            toggled: Persistent.states.wallhaven.order === "asc"
                            downAction: () => Persistent.states.wallhaven.order = "asc"
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            FilterSectionLabel { text: Translation.tr("Min resolution") }
                            FilterTextField {
                                Layout.fillWidth: true
                                placeholderText: "1920x1080"
                                text: Persistent.states.wallhaven.atleast
                                onEditingFinished: Persistent.states.wallhaven.atleast = text.trim()
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            FilterSectionLabel { text: Translation.tr("Ratios") }
                            FilterTextField {
                                Layout.fillWidth: true
                                placeholderText: "16x9,landscape"
                                text: Persistent.states.wallhaven.ratios
                                onEditingFinished: Persistent.states.wallhaven.ratios = text.trim()
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        FilterSectionLabel { text: Translation.tr("Exact resolutions") }
                        FilterTextField {
                            Layout.fillWidth: true
                            placeholderText: "2560x1440,3840x2160"
                            text: Persistent.states.wallhaven.resolutions
                            onEditingFinished: Persistent.states.wallhaven.resolutions = text.trim()
                        }
                    }

                    FilterSectionLabel { text: Translation.tr("Download folder") }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        FilterTextField {
                            Layout.fillWidth: true
                            placeholderText: Directories.booruDownloads
                            text: Persistent.states.wallhaven.downloadFolder
                            onEditingFinished: Persistent.states.wallhaven.downloadFolder = text.trim()
                        }
                        FilterIconButton {
                            buttonIcon: "folder_open"
                            tooltipText: Translation.tr("Browse…")
                            onClicked: {
                                if (!folderPickerProcess.running)
                                    folderPickerProcess.running = true
                            }
                        }
                        FilterIconButton {
                            buttonIcon: "restart_alt"
                            tooltipText: Translation.tr("Reset to default")
                            visible: root.customDownloadFolder.length > 0
                            onClicked: Persistent.states.wallhaven.downloadFolder = ""
                        }
                    }
                }
            }
        }

        Rectangle {
            id: tagInputContainer
            property real columnSpacing: 5
            Layout.fillWidth: true
            radius: Appearance.rounding.normal - root.padding
            color: Appearance.angelEverywhere ? Appearance.angel.colGlassCard
                : Appearance.inirEverywhere ? Appearance.inir.colLayer2 : Appearance.auroraEverywhere ? Appearance.aurora.colElevatedSurface : Appearance.colors.colLayer2
            implicitWidth: tagInputField.implicitWidth
            implicitHeight: Math.max(inputFieldRowLayout.implicitHeight + inputFieldRowLayout.anchors.topMargin
                + commandButtonsRow.implicitHeight + commandButtonsRow.anchors.bottomMargin + columnSpacing, 45)
            clip: true

            Behavior on implicitHeight {
                enabled: Appearance.animationsEnabled
                animation: NumberAnimation { duration: Appearance.animation.elementMove.duration; easing.type: Appearance.animation.elementMove.type; easing.bezierCurve: Appearance.animation.elementMove.bezierCurve }
            }

            RowLayout {
                id: inputFieldRowLayout
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.topMargin: 5
                spacing: 0

                StyledTextArea {
                    id: tagInputField
                    wrapMode: TextArea.Wrap
                    Layout.fillWidth: true
                    padding: 10
                    color: activeFocus ? Appearance.colors.colOnSurface : Appearance.colors.colOnSurfaceVariant
                    renderType: Text.NativeRendering
                    placeholderText: Translation.tr('Enter tags, or "%1" for commands').arg(root.commandPrefix)
                    background: null

                    function accept() {
                        root.handleInput(text)
                        text = ""
                    }

                    Keys.onPressed: (event) => {
                        if ((event.key === Qt.Key_Enter || event.key === Qt.Key_Return)) {
                            if (event.modifiers & Qt.ShiftModifier) {
                                tagInputField.insert(tagInputField.cursorPosition, "\n")
                                event.accepted = true
                            } else {
                                const inputText = tagInputField.text
                                root.handleInput(inputText)
                                tagInputField.clear()
                                event.accepted = true
                            }
                        }
                    }
                }

                RippleButton {
                    id: sendButton
                    Layout.alignment: Qt.AlignTop
                    Layout.rightMargin: 5
                    implicitWidth: 40
                    implicitHeight: 40
                    buttonRadius: Appearance.rounding.small
                    enabled: tagInputField.text.length > 0
                    toggled: enabled

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: sendButton.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            const inputText = tagInputField.text
                            root.handleInput(inputText)
                            tagInputField.clear()
                        }
                    }

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        iconSize: 22
                        color: sendButton.enabled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2Disabled
                        text: "arrow_upward"
                    }
                }
            }

            RowLayout {
                id: commandButtonsRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 5
                anchors.leftMargin: 5
                anchors.rightMargin: 5
                spacing: 5

                ApiInputBoxIndicator {
                    icon: "image"
                    text: "wallhaven.cc"
                    tooltipText: Translation.tr("Search wallpapers from wallhaven.cc\nUse %1safe or %2lewd to toggle NSFW (requires API key)")
                        .arg(root.commandPrefix).arg(root.commandPrefix)
                }

                StyledText {
                    font.pixelSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnLayer1
                    text: "•"
                }

                MouseArea {
                    visible: width > 0
                    implicitWidth: switchesRow.implicitWidth
                    Layout.fillHeight: true

                    hoverEnabled: true
                    PointingHandInteraction {}
                    onPressed: {
                        nsfwSwitch.checked = !nsfwSwitch.checked
                    }

                    RowLayout {
                        id: switchesRow
                        spacing: 5
                        anchors.centerIn: parent

                        StyledText {
                            Layout.fillHeight: true
                            Layout.leftMargin: 10
                            Layout.alignment: Qt.AlignVCenter
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: nsfwSwitch.enabled ? Appearance.colors.colOnLayer1 : Appearance.colors.colOutline
                            text: Translation.tr("Allow NSFW")
                        }
                        StyledSwitch {
                            id: nsfwSwitch
                            enabled: true
                            scale: 0.6
                            Layout.alignment: Qt.AlignVCenter
                            checked: Persistent.states.booru.allowNsfw
                            onCheckedChanged: {
                                Persistent.states.booru.allowNsfw = checked;
                            }
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                RippleButton {
                    id: filterToggleButton
                    implicitWidth: 30
                    implicitHeight: 30
                    buttonRadius: Appearance.rounding.small
                    toggled: root.showFilters
                    onClicked: root.showFilters = !root.showFilters
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        iconSize: 18
                        text: "tune"
                        color: filterToggleButton.toggled ? Appearance.m3colors.m3onPrimary
                            : Appearance.inirEverywhere ? Appearance.inir.colText : Appearance.colors.colOnLayer2
                    }
                    StyledToolTip {
                        text: Translation.tr("Search filters")
                    }
                }

                ButtonGroup {
                    padding: 0
                    Repeater {
                        id: commandRepeater
                        model: commandButtonsRow.commandsShown
                        delegate: ApiCommandButton {
                            property string commandRepresentation: `${root.commandPrefix}${modelData.name}`
                            buttonText: commandRepresentation
                            colBackground: Appearance.angelEverywhere ? Appearance.angel.colGlassCard
                                : Appearance.auroraEverywhere ? "transparent" : Appearance.colors.colLayer2

                            downAction: () => {
                                if (modelData.sendDirectly) {
                                    root.handleInput(commandRepresentation)
                                } else {
                                    tagInputField.text = commandRepresentation + " "
                                    tagInputField.cursorPosition = tagInputField.text.length
                                    tagInputField.forceActiveFocus()
                                }
                                if (modelData.name === "clear") {
                                    tagInputField.text = ""
                                }
                            }
                        }
                    }

                    property var commandsShown: [
                        {
                            name: "clear",
                            sendDirectly: true,
                        },
                        {
                            name: "next",
                            sendDirectly: true,
                        },
                    ]
                }
            }
        }
    }

    // System folder picker for the download folder (kdialog, same convention as switchwall.sh)
    Process {
        id: folderPickerProcess
        command: ["/usr/bin/kdialog", "--getexistingdirectory", root.downloadPath, "--title", Translation.tr("Choose download folder")]
        stdout: StdioCollector {
            onStreamFinished: {
                const path = text.trim()
                if (path.length > 0) {
                    Persistent.states.wallhaven.downloadFolder = path
                }
            }
        }
    }

    component FilterSectionLabel: StyledText {
        font.pixelSize: Appearance.font.pixelSize.smaller
        font.weight: Font.Medium
        color: Appearance.inirEverywhere ? Appearance.inir.colTextSecondary
            : Appearance.angelEverywhere ? Appearance.angel.colTextSecondary
            : Appearance.colors.colSubtext
    }

    component FilterChip: RippleButton {
        id: chip
        property string chipText
        implicitHeight: 26
        implicitWidth: chipLabel.implicitWidth + 20
        buttonRadius: Appearance.rounding.full
        opacity: enabled ? 1 : 0.5
        contentItem: StyledText {
            id: chipLabel
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: Appearance.font.pixelSize.smaller
            text: chip.chipText
            color: chip.toggled ? Appearance.m3colors.m3onPrimary
                : Appearance.inirEverywhere ? Appearance.inir.colText : Appearance.colors.colOnLayer2
        }
    }

    component FilterIconButton: RippleButton {
        id: iconBtn
        property string buttonIcon
        property string tooltipText
        implicitWidth: 30
        implicitHeight: 30
        buttonRadius: Appearance.rounding.small
        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            iconSize: 17
            text: iconBtn.buttonIcon
            color: Appearance.inirEverywhere ? Appearance.inir.colText : Appearance.colors.colOnLayer2
        }
        StyledToolTip {
            text: iconBtn.tooltipText
        }
    }

    component FilterTextField: StyledTextArea {
        id: filterField
        wrapMode: TextEdit.NoWrap
        padding: 6
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.inirEverywhere ? Appearance.inir.colText : Appearance.m3colors.m3onSurface
        background: Rectangle {
            radius: Appearance.rounding.small
            color: Appearance.inirEverywhere ? Appearance.inir.colLayer1
                : Appearance.angelEverywhere ? Appearance.angel.colGlassCardActive
                : Appearance.colors.colLayer1
        }
        Keys.onPressed: (event) => {
            // editingFinished fires on focus loss; Enter should commit too
            if (event.key === Qt.Key_Enter || event.key === Qt.Key_Return) {
                filterField.editingFinished()
                event.accepted = true
            }
        }
    }
}
