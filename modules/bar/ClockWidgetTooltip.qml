import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import "../sidebarRight/calendar/calendar_layout.js" as CalendarLayout

StyledPopup {
    id: root
    property string formattedDate: Qt.locale().toString(DateTime.clock.date, "dddd, MMMM dd, yyyy")
    property string formattedTime: DateTime.time
    property string formattedUptime: DateTime.uptime
    property string todosSection: getUpcomingTodos()

    property var locale: Qt.locale()
    property var calendarLayout: CalendarLayout.getCalendarLayout(DateTime.clock.date, true, locale.firstDayOfWeek)
    readonly property color colPrimary: Appearance.inirEverywhere ? Appearance.inir.colPrimary
        : Appearance.angelEverywhere ? Appearance.angel.colPrimary : Appearance.colors.colPrimary
    readonly property color colOnPrimary: Appearance.inirEverywhere ? Appearance.inir.colOnPrimary
        : Appearance.angelEverywhere ? Appearance.angel.colOnPrimary : Appearance.colors.colOnPrimary

    property list<string> weekDayLabels: {
        const labels = []
        const fdow = locale.firstDayOfWeek
        for (let i = 0; i < 7; i++) {
            // Qt day-of-week numbering: 1=Mon..7=Sun
            const dayNum = ((fdow - 1 + i) % 7) + 1
            labels.push(locale.dayName(dayNum, Locale.NarrowFormat))
        }
        return labels
    }

    // Resolve a calendar cell (day + in-month flag) to a Date.
    // Uses the cell's monthDiff via the shared helper (heuristic fallback).
    function dateForCell(cellData) {
        return CalendarLayout.dateForCell(cellData, DateTime.clock.date)
    }

    function hasEventsOnDate(date) {
        if (!date) return false
        if (Events.getAllEventsForDate(date).length > 0) return true
        return (CalendarSync.getEventsForDate(date) || []).length > 0
    }

    // Merged local + external events for the next 7 days
    readonly property var upcomingEvents: {
        const _refresh = DateTime.clock.date
        const now = new Date()
        const startDay = new Date(now)
        startDay.setHours(0, 0, 0, 0)

        const result = Events.getUpcomingEvents(7).map(e => ({
            date: new Date(e.dateTime),
            title: e.title,
            allDay: false,
            color: root.colPrimary
        }))

        const seen = new Set()
        for (let i = 0; i < 7; i++) {
            const d = new Date(startDay)
            d.setDate(d.getDate() + i)
            const dayEvents = CalendarSync.getEventsForDate(d) || []
            for (const e of dayEvents) {
                const start = new Date(e.startDate)
                if (!e.allDay && start < now) continue
                const key = (e.uid ?? e.title ?? "") + (e.startDate ?? "")
                if (seen.has(key)) continue
                seen.add(key)
                result.push({
                    date: start,
                    title: e.title ?? "",
                    allDay: !!e.allDay,
                    color: e.sourceColor ?? root.colPrimary
                })
            }
        }

        result.sort((a, b) => a.date - b.date)
        return result
    }

    function formatEventTime(event) {
        if (event.allDay) return locale.toString(event.date, "ddd d")
        return locale.toString(event.date, "ddd d") + " " + locale.toString(event.date, "HH:mm")
    }

    function getUpcomingTodos() {
        const unfinishedTodos = Todo.list.filter(function (item) {
            return !item.done;
        });
        if (unfinishedTodos.length === 0) {
            return Translation.tr("No pending tasks");
        }

        // Limit to first 5 todos to keep popup manageable
        const limitedTodos = unfinishedTodos.slice(0, 5);
        let todoText = limitedTodos.map(function (item, index) {
            return `${index + 1}. ${item.content}`;
        }).join('\n');

        if (unfinishedTodos.length > 5) {
            todoText += `\n${Translation.tr("... and %1 more").arg(unfinishedTodos.length - 5)}`;
        }

        return todoText;
    }

    ColumnLayout {
        id: columnLayout
        anchors.centerIn: parent
        spacing: 4

        // Date + Time row
        Row {
            spacing: 5

            MaterialSymbol {
                anchors.verticalCenter: parent.verticalCenter
                fill: 0
                font.weight: Font.Medium
                text: "calendar_month"
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnSurfaceVariant
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignLeft
                color: Appearance.colors.colOnSurfaceVariant
                text: `${root.formattedDate}`
                font.weight: Font.Medium
            }
        }

        // Mini month calendar with event dots
        GridLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 2
            columns: 7
            columnSpacing: 2
            rowSpacing: 1

            Repeater {
                model: root.weekDayLabels
                delegate: StyledText {
                    required property string modelData
                    Layout.preferredWidth: 22
                    horizontalAlignment: Text.AlignHCenter
                    text: modelData
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.Medium
                    color: Appearance.colors.colSubtext
                }
            }

            Repeater {
                model: 42
                delegate: Item {
                    id: dayCell
                    required property int index
                    readonly property var cellData: root.calendarLayout[Math.floor(index / 7)]?.[index % 7] ?? null
                    readonly property var cellDate: root.dateForCell(cellData)
                    readonly property bool isToday: (cellData?.today ?? 0) === 1
                    readonly property bool inMonth: (cellData?.today ?? -1) !== -1
                    readonly property bool hasEvents: root.hasEventsOnDate(cellDate)

                    Layout.preferredWidth: 22
                    Layout.preferredHeight: 20

                    Rectangle {
                        anchors.centerIn: parent
                        width: 19
                        height: 19
                        radius: Appearance.rounding.full
                        color: dayCell.isToday ? root.colPrimary : "transparent"
                    }

                    StyledText {
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: -1
                        text: dayCell.cellData?.day ?? ""
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.family: Appearance.font.family.numbers
                        color: dayCell.isToday ? root.colOnPrimary
                            : dayCell.inMonth ? Appearance.colors.colOnSurfaceVariant
                            : Appearance.colors.colSubtext
                        opacity: dayCell.inMonth ? 1 : 0.45
                    }

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        width: 4
                        height: 4
                        radius: 2
                        visible: dayCell.hasEvents
                        color: dayCell.isToday ? root.colOnPrimary : root.colPrimary
                    }
                }
            }
        }

        // Upcoming events (next 7 days)
        Column {
            spacing: 2
            Layout.fillWidth: true
            Layout.topMargin: 4

            Row {
                spacing: 4
                MaterialSymbol {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "event_upcoming"
                    color: Appearance.colors.colOnSurfaceVariant
                    font.pixelSize: Appearance.font.pixelSize.large
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Translation.tr("Next 7 days:")
                    color: Appearance.colors.colOnSurfaceVariant
                }
            }

            StyledText {
                visible: root.upcomingEvents.length === 0
                color: Appearance.colors.colSubtext
                text: Translation.tr("No upcoming events")
            }

            Repeater {
                model: root.upcomingEvents.slice(0, 6)
                delegate: Row {
                    required property var modelData
                    spacing: 5

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 5
                        height: 5
                        radius: 2.5
                        color: modelData.color
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.formatEventTime(modelData)
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.title
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnSurfaceVariant
                        elide: Text.ElideRight
                        width: Math.min(implicitWidth, 180)
                    }
                }
            }

            StyledText {
                visible: root.upcomingEvents.length > 6
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
                text: Translation.tr("... and %1 more").arg(root.upcomingEvents.length - 6)
            }
        }

        // Uptime row
        RowLayout {
            spacing: 5
            Layout.fillWidth: true
            Layout.topMargin: 4
            MaterialSymbol {
                text: "timelapse"
                color: Appearance.colors.colOnSurfaceVariant
                font.pixelSize: Appearance.font.pixelSize.large
            }
            StyledText {
                text: Translation.tr("System uptime:")
                color: Appearance.colors.colOnSurfaceVariant
            }
            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignRight
                color: Appearance.colors.colOnSurfaceVariant
                text: root.formattedUptime
            }
        }

        // Tasks
        Column {
            spacing: 0
            Layout.fillWidth: true

            Row {
                spacing: 4
                MaterialSymbol {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "checklist"
                    color: Appearance.colors.colOnSurfaceVariant
                    font.pixelSize: Appearance.font.pixelSize.large
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Translation.tr("To Do:")
                    color: Appearance.colors.colOnSurfaceVariant
                }
            }

            StyledText {
                horizontalAlignment: Text.AlignLeft
                wrapMode: Text.Wrap
                color: Appearance.colors.colOnSurfaceVariant
                text: root.todosSection
            }
        }
    }
}
