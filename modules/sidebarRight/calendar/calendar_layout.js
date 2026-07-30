const weekDays = [ // MONDAY IS THE FIRST DAY OF THE WEEK :HESRIGHTYOUKNOW:
    { day: 'Mo', today: 0 },
    { day: 'Tu', today: 0 },
    { day: 'We', today: 0 },
    { day: 'Th', today: 0 },
    { day: 'Fr', today: 0 },
    { day: 'Sa', today: 0 },
    { day: 'Su', today: 0 },
]

function checkLeapYear(year) {
    return (
        year % 400 == 0 ||
        (year % 4 == 0 && year % 100 != 0));
}

function getMonthDays(month, year) {
    const leapYear = checkLeapYear(year);
    if ((month <= 7 && month % 2 == 1) || (month >= 8 && month % 2 == 0)) return 31;
    if (month == 2 && leapYear) return 29;
    if (month == 2 && !leapYear) return 28;
    return 30;
}

// Neighbouring month lengths delegate to getMonthDays with proper year
// wrapping. They used to re-derive lengths with an inverted parity test on the
// *viewed* month, which got August wrong (prev of Aug read as 30, so the August
// grid dropped Jul 31) and July's next month too (Aug read as 30 — latent, as
// trailing cells never reach day 30).
function getNextMonthDays(month, year) {
    return month == 12 ? getMonthDays(1, year + 1) : getMonthDays(month + 1, year);
}

function getPrevMonthDays(month, year) {
    return month == 1 ? getMonthDays(12, year - 1) : getMonthDays(month - 1, year);
}

function getDateInXMonthsTime(x) {
    var currentDate = new Date(); // Get the current date
    if (x == 0) return currentDate; // If x is 0, return the current date

    var targetMonth = currentDate.getMonth() + x; // Calculate the target month
    var targetYear = currentDate.getFullYear(); // Get the current year

    // Adjust the year and month if necessary
    targetYear += Math.floor(targetMonth / 12);
    targetMonth = (targetMonth % 12 + 12) % 12;

    // Create a new date object with the target year and month
    var targetDate = new Date(targetYear, targetMonth, 1);

    // Set the day to the last day of the month to get the desired date
    // targetDate.setDate(0);

    return targetDate;
}

function getCalendarLayout(dateObject, highlight, firstDayOfWeek = 1) {
    if (!dateObject) dateObject = new Date();
    // Convert JS getDay() (0=Sun) to offset from firstDayOfWeek
    const weekday = (dateObject.getDay() - firstDayOfWeek + 7) % 7;
    const day = dateObject.getDate();
    const month = dateObject.getMonth() + 1;
    const year = dateObject.getFullYear();
    const weekdayOfMonthFirst = (weekday + 35 - (day - 1)) % 7;
    const daysInMonth = getMonthDays(month, year);
    const daysInNextMonth = getNextMonthDays(month, year);
    const daysInPrevMonth = getPrevMonthDays(month, year);

    // Fill
    var monthDiff = (weekdayOfMonthFirst == 0 ? 0 : -1);
    var toFill, dim;
    if(weekdayOfMonthFirst == 0) {
        toFill = 1;
        dim = daysInMonth;
    }
    else {
        toFill = (daysInPrevMonth - (weekdayOfMonthFirst - 1));
        dim = daysInPrevMonth;
    }
    var calendar = [...Array(6)].map(() => Array(7));
    var i = 0, j = 0;
    while (i < 6 && j < 7) {
        calendar[i][j] = {
            "day": toFill,
            // Month offset of this cell relative to the viewed month:
            // -1 = previous month, 0 = current month, 1 = next month.
            // Needed to resolve cells to real dates — `today` alone cannot
            // distinguish trailing (next-month) cells from leading ones.
            "monthDiff": monthDiff,
            "today": ((toFill == day && monthDiff == 0 && highlight) ? 1 : (
                monthDiff == 0 ? 0 :
                    -1
            ))
        };
        // Increment
        toFill++;
        if (toFill > dim) { // Next month?
            monthDiff++;
            if (monthDiff == 0)
                dim = daysInMonth;
            else if (monthDiff == 1)
                dim = daysInNextMonth;
            toFill = 1;
        }
        // Next tile
        j++;
        if (j == 7) {
            j = 0;
            i++;
        }

    }
    return calendar;
}

// ── Shared merged-event helpers ────────────────────────────────────────────
// Both the sidebar calendar and the bar clock tooltip merge local events
// (Events service) with external calendars (CalendarSync service) in the
// same way. Centralized here so the merge logic lives in exactly one place.
// The service singletons are passed in as arguments — this JS library must
// stay import-free (it is shared by multiple QML modules).

// Resolve a layout cell to a real Date. `viewingDate` is any date inside the
// viewed month; the cell carries `monthDiff` (-1/0/1) from getCalendarLayout.
// Falls back to the day-number heuristic for legacy cells without monthDiff.
function dateForCell(cellData, viewingDate) {
    if (!cellData || !viewingDate) return null;
    const year = viewingDate.getFullYear();
    const month = viewingDate.getMonth();
    if (cellData.monthDiff !== undefined)
        return new Date(year, month + cellData.monthDiff, cellData.day);
    if (cellData.today === -1) {
        return cellData.day > 15
            ? new Date(year, month - 1, cellData.day)
            : new Date(year, month + 1, cellData.day);
    }
    return new Date(year, month, cellData.day);
}

// Local events normalized to the external-event shape ({source, startDate}).
function normalizedLocalEventsForDate(Events, date) {
    return Events.getAllEventsForDate(date).map(function (e) {
        return Object.assign({}, e, {
            source: "local",
            startDate: e.dateTime
        });
    });
}

// Merged local + external events for a date, external first-in for stable order.
function mergedEventsForDate(Events, CalendarSync, date) {
    const localEvents = normalizedLocalEventsForDate(Events, date);
    const externalEvents = CalendarSync.getEventsForDate(date) || [];
    return localEvents.concat(externalEvents);
}

// Total event count for a date (local + external), for grid dot indicators.
function eventCountForDate(Events, CalendarSync, date) {
    return Events.getEventsForDate(date).length
        + (CalendarSync.getEventsForDate(date) || []).length;
}

