import SwiftUI

/// A calendar day with no time of day.
struct DayStamp: Codable, Hashable, Comparable, Sendable {
    var year: Int
    /// 1 through 12.
    var month: Int
    /// 1 through the month's length.
    var day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    init(_ date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 2000, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    static func today(_ now: Date = Date()) -> DayStamp { DayStamp(now) }

    static func < (lhs: DayStamp, rhs: DayStamp) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    /// Nine in the morning of that day, in the current calendar.
    var date: Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: 9)) ?? Date()
    }

    static func daysIn(month: Int, year: Int) -> Int {
        let calendar = Calendar.current
        guard let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let range = calendar.range(of: .day, in: .month, for: first) else { return 31 }
        return range.count
    }

    /// The same month with the day kept inside it.
    var clamped: DayStamp {
        DayStamp(year: year, month: month, day: min(max(day, 1), Self.daysIn(month: month, year: year)))
    }

    func adding(days: Int) -> DayStamp {
        DayStamp(Calendar.current.date(byAdding: .day, value: days, to: date) ?? date)
    }

    /// Whole days from `other` to this day; negative when this day is earlier.
    func days(since other: DayStamp) -> Int {
        let calendar = Calendar.current
        let from = calendar.startOfDay(for: other.date)
        let to = calendar.startOfDay(for: date)
        return calendar.dateComponents([.day], from: from, to: to).day ?? 0
    }
}

struct Reminder: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var title: String
    var note: String
    var day: DayStamp
    /// Time of day, 24-hour.
    var hour: Int
    var minute: Int
    /// 0 through 1 around the colour wheel.
    var hue: Double
    /// 0 at the top of the spectrum (pastel) through 1 at the bottom (dark); 0.5 is vivid.
    var tone: Double
    var createdAt: Date
    var completedAt: Date?
    /// The day the due strip was shown, so it shows once.
    var announcedOn: DayStamp?

    init(
        id: UUID = UUID(),
        title: String,
        note: String = "",
        day: DayStamp,
        hour: Int = 9,
        minute: Int = 0,
        hue: Double,
        tone: Double = NotaColor.defaultTone,
        createdAt: Date = Date(),
        completedAt: Date? = nil,
        announcedOn: DayStamp? = nil
    ) {
        self.id = id
        self.title = title
        self.note = note
        self.day = day
        self.hour = hour
        self.minute = minute
        self.hue = hue
        self.tone = tone
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.announcedOn = announcedOn
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, note, day, hour, minute, hue, tone, createdAt, completedAt, announcedOn
    }

    /// A reminder saved before the time of day existed is due at nine.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        note = try values.decodeIfPresent(String.self, forKey: .note) ?? ""
        day = try values.decode(DayStamp.self, forKey: .day)
        hour = try values.decodeIfPresent(Int.self, forKey: .hour) ?? 9
        minute = try values.decodeIfPresent(Int.self, forKey: .minute) ?? 0
        hue = try values.decodeIfPresent(Double.self, forKey: .hue) ?? NotaColor.defaultHue
        tone = try values.decodeIfPresent(Double.self, forKey: .tone) ?? NotaColor.defaultTone
        createdAt = try values.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        completedAt = try values.decodeIfPresent(Date.self, forKey: .completedAt)
        announcedOn = try values.decodeIfPresent(DayStamp.self, forKey: .announcedOn)
    }

    var isDone: Bool { completedAt != nil }

    var color: Color { NotaColor.color(hue: hue, tone: tone) }

    /// The moment it is due.
    var dueDate: Date {
        Calendar.current.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: hour, minute: minute)) ?? day.date
    }

    var time: String { NotaDate.time(hour: hour, minute: minute) }

    func isOverdue(now: Date, today: DayStamp) -> Bool { !isDone && (day < today || (day == today && dueDate <= now)) }

    func isDue(today: DayStamp) -> Bool { !isDone && day == today }

    /// Due today and the time has come.
    func isRinging(now: Date, today: DayStamp) -> Bool { isDue(today: today) && dueDate <= now }
}

enum NotaColor {
    static let defaultTone = 0.5

    /// A colour on the spectrum: the hue across, the tone down (pastel, vivid, dark).
    static func color(hue: Double, tone: Double = defaultTone) -> Color {
        let t = min(max(tone, 0), 1)
        let saturation = t < 0.5 ? 0.22 + (0.72 - 0.22) * (t / 0.5) : 0.72
        let brightness = t < 0.5 ? 0.96 : 0.96 - 0.56 * ((t - 0.5) / 0.5)
        return Color(hue: hue.truncatingRemainder(dividingBy: 1), saturation: saturation, brightness: brightness)
    }

    /// The whole wheel, for the gradient line.
    static let spectrum: [Color] = (0...24).map { color(hue: Double($0) / 24) }

    /// A spoken name for the hue.
    static func name(hue: Double) -> String {
        let names = ["red", "orange", "yellow", "lime", "green", "mint", "cyan", "sky blue", "blue", "indigo", "purple", "pink"]
        let index = Int((hue.truncatingRemainder(dividingBy: 1) * Double(names.count)).rounded()) % names.count
        return names[index]
    }

    static let defaultHue = 0.6
}

enum NotaDate {
    private static let calendar = Calendar.current

    static func time(hour: Int, minute: Int) -> String {
        String(format: "%02d:%02d", hour, minute)
    }

    static var monthNames: [String] { calendar.shortMonthSymbols }

    static func monthName(_ month: Int) -> String {
        let names = monthNames
        guard names.indices.contains(month - 1) else { return "" }
        return names[month - 1]
    }

    /// "Today", "Tomorrow", "Yesterday", else the short date.
    static func label(_ day: DayStamp, today: DayStamp) -> String {
        switch day.days(since: today) {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case -1: return "Yesterday"
        default: return short(day, today: today)
        }
    }

    /// "Mon 20 Oct", with the year when it is not this one.
    static func short(_ day: DayStamp, today: DayStamp) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate(day.year == today.year ? "EEE d MMM" : "d MMM yyyy")
        return formatter.string(from: day.date)
    }

    /// "Mon, 19 Jan 2026", for a chip.
    static func chip(_ day: DayStamp, today: DayStamp) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("EEE d MMM yyyy")
        return formatter.string(from: day.date)
    }

    /// "Thursday, 16 October 2026".
    static func long(_ day: DayStamp) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("EEEE d MMMM yyyy")
        return formatter.string(from: day.date)
    }

    /// "In 3 days", "2 weeks ago", "Today".
    static func distance(_ day: DayStamp, today: DayStamp) -> String {
        let diff = day.days(since: today)
        switch diff {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case -1: return "Yesterday"
        default: break
        }
        let count = abs(diff)
        let unit: String
        let amount: Int
        if count < 14 {
            amount = count
            unit = "day"
        } else if count < 60 {
            amount = count / 7
            unit = "week"
        } else if count < 365 {
            amount = count / 30
            unit = "month"
        } else {
            amount = count / 365
            unit = "year"
        }
        let words = "\(amount) \(unit)\(amount == 1 ? "" : "s")"
        return diff > 0 ? "In \(words)" : "\(words) ago"
    }
}
