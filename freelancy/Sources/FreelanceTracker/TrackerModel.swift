import Foundation
import SwiftUI

public struct TrackerCurrency: Hashable, Sendable, Identifiable {
    public let code: String

    public let symbol: String

    public let name: String

    public let symbolIsSuffix: Bool

    public var id: String { code }

    public init(code: String, symbol: String, name: String, symbolIsSuffix: Bool = false) {
        self.code = code
        self.symbol = symbol
        self.name = name
        self.symbolIsSuffix = symbolIsSuffix
    }

    public static let all: [TrackerCurrency] = [
        TrackerCurrency(code: "USD", symbol: "$", name: "US dollar"),
        TrackerCurrency(code: "EUR", symbol: "€", name: "Euro"),
        TrackerCurrency(code: "GBP", symbol: "£", name: "British pound"),
        TrackerCurrency(code: "CHF", symbol: "CHF", name: "Swiss franc", symbolIsSuffix: true),
        TrackerCurrency(code: "JPY", symbol: "¥", name: "Japanese yen"),
        TrackerCurrency(code: "CNY", symbol: "CN¥", name: "Chinese yuan"),
        TrackerCurrency(code: "RUB", symbol: "₽", name: "Russian ruble"),
        TrackerCurrency(code: "UAH", symbol: "₴", name: "Ukrainian hryvnia"),
        TrackerCurrency(code: "BYN", symbol: "Br", name: "Belarusian ruble", symbolIsSuffix: true),
        TrackerCurrency(code: "KZT", symbol: "₸", name: "Kazakhstani tenge"),
        TrackerCurrency(code: "GEL", symbol: "₾", name: "Georgian lari"),
        TrackerCurrency(code: "AMD", symbol: "֏", name: "Armenian dram"),
        TrackerCurrency(code: "TRY", symbol: "₺", name: "Turkish lira"),
        TrackerCurrency(code: "AED", symbol: "AED", name: "UAE dirham", symbolIsSuffix: true),
        TrackerCurrency(code: "ILS", symbol: "₪", name: "Israeli shekel"),
        TrackerCurrency(code: "INR", symbol: "₹", name: "Indian rupee"),
        TrackerCurrency(code: "PLN", symbol: "zł", name: "Polish złoty", symbolIsSuffix: true),
        TrackerCurrency(code: "CZK", symbol: "Kč", name: "Czech koruna", symbolIsSuffix: true),
        TrackerCurrency(code: "SEK", symbol: "kr", name: "Swedish krona", symbolIsSuffix: true),
        TrackerCurrency(code: "NOK", symbol: "kr", name: "Norwegian krone", symbolIsSuffix: true),
        TrackerCurrency(code: "DKK", symbol: "kr", name: "Danish krone", symbolIsSuffix: true),
        TrackerCurrency(code: "CAD", symbol: "CA$", name: "Canadian dollar"),
        TrackerCurrency(code: "AUD", symbol: "A$", name: "Australian dollar"),
        TrackerCurrency(code: "BRL", symbol: "R$", name: "Brazilian real"),
        TrackerCurrency(code: "MXN", symbol: "MX$", name: "Mexican peso"),
        TrackerCurrency(code: "SGD", symbol: "S$", name: "Singapore dollar"),
        TrackerCurrency(code: "HKD", symbol: "HK$", name: "Hong Kong dollar"),
        TrackerCurrency(code: "KRW", symbol: "₩", name: "South Korean won")
    ]

    public static let usd = all[0]

    public static func named(_ code: String) -> TrackerCurrency {
        all.first { $0.code == code } ?? usd
    }

    private var usesWholeAmounts: Bool { code == "JPY" || code == "KRW" }

    public func format(_ amount: Double, compact: Bool = false) -> String {
        let fraction = usesWholeAmounts || (compact && amount >= 1000) ? 0 : 2
        let number = amount.formatted(
            .number
                .precision(.fractionLength(fraction))
                .grouping(compact ? .never : .automatic)
                .locale(Locale(identifier: "en_US"))
        )
        return attach(number)
    }

    public func formatRate(_ rate: Double) -> String {
        formatAmount(rate) + "/h"
    }

    public func formatAmount(_ amount: Double) -> String {
        let isWhole = amount == amount.rounded()
        let number = amount.formatted(
            .number
                .precision(.fractionLength(isWhole ? 0 : 2))
                .grouping(.never)
                .locale(Locale(identifier: "en_US"))
        )
        return attach(number)
    }

    private func attach(_ number: String) -> String {
        symbolIsSuffix ? "\(number) \(symbol)" : "\(symbol)\(number)"
    }
}

public enum ProjectIcon: String, Codable, CaseIterable, Sendable, Identifiable {
    case briefcase, paintbrush, hammer, laptop, camera, music, book, globe
    case chart, box, pencil, megaphone, cart, game, leaf, heart

    public var id: String { rawValue }

    public var symbol: String {
        switch self {
        case .briefcase: "briefcase"
        case .paintbrush: "paintbrush.pointed"
        case .hammer: "hammer"
        case .laptop: "laptopcomputer"
        case .camera: "camera"
        case .music: "music.note"
        case .book: "book.closed"
        case .globe: "globe"
        case .chart: "chart.line.uptrend.xyaxis"
        case .box: "shippingbox"
        case .pencil: "pencil.line"
        case .megaphone: "megaphone"
        case .cart: "cart"
        case .game: "gamecontroller"
        case .leaf: "leaf"
        case .heart: "heart"
        }
    }

    public var name: String {
        switch self {
        case .briefcase: "Briefcase"
        case .paintbrush: "Paintbrush"
        case .hammer: "Hammer"
        case .laptop: "Laptop"
        case .camera: "Camera"
        case .music: "Music"
        case .book: "Book"
        case .globe: "Globe"
        case .chart: "Chart"
        case .box: "Box"
        case .pencil: "Pencil"
        case .megaphone: "Megaphone"
        case .cart: "Cart"
        case .game: "Game controller"
        case .leaf: "Leaf"
        case .heart: "Heart"
        }
    }
}

public enum ProjectColor: String, Codable, CaseIterable, Sendable, Identifiable {
    case cyan, blue, purple, pink, red, orange, yellow, green, mint

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .cyan: "Cyan"
        case .blue: "Blue"
        case .purple: "Purple"
        case .pink: "Pink"
        case .red: "Red"
        case .orange: "Orange"
        case .yellow: "Yellow"
        case .green: "Green"
        case .mint: "Mint"
        }
    }

    public var color: Color {
        switch self {
        case .cyan: Color(red: 0.36, green: 0.90, blue: 1.00)
        case .blue: Color(red: 0.42, green: 0.64, blue: 1.00)
        case .purple: Color(red: 0.70, green: 0.56, blue: 1.00)
        case .pink: Color(red: 1.00, green: 0.52, blue: 0.76)
        case .red: Color(red: 1.00, green: 0.44, blue: 0.44)
        case .orange: Color(red: 1.00, green: 0.63, blue: 0.32)
        case .yellow: Color(red: 1.00, green: 0.85, blue: 0.36)
        case .green: Color(red: 0.46, green: 0.90, blue: 0.56)
        case .mint: Color(red: 0.42, green: 0.92, blue: 0.80)
        }
    }

    public static func suggested(forProjectNumber number: Int) -> ProjectColor {
        allCases[max(0, number - 1) % allCases.count]
    }
}

public struct Project: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID

    public var name: String

    public var rate: Double

    public var currencyCode: String
    public let createdAt: Date

    public var currentSessionID: UUID?

    public var color: ProjectColor
    public var icon: ProjectIcon

    public init(
        id: UUID = UUID(),
        name: String,
        rate: Double,
        currencyCode: String,
        color: ProjectColor = .cyan,
        icon: ProjectIcon = .briefcase,
        createdAt: Date = Date(),
        currentSessionID: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.rate = rate
        self.currencyCode = currencyCode
        self.color = color
        self.icon = icon
        self.createdAt = createdAt
        self.currentSessionID = currentSessionID
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, rate, currencyCode, createdAt, currentSessionID, color, icon
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        rate = try container.decode(Double.self, forKey: .rate)
        currencyCode = try container.decode(String.self, forKey: .currencyCode)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        currentSessionID = try container.decodeIfPresent(UUID.self, forKey: .currentSessionID)
        color = (try? container.decodeIfPresent(ProjectColor.self, forKey: .color)) ?? .cyan
        icon = (try? container.decodeIfPresent(ProjectIcon.self, forKey: .icon)) ?? .briefcase
    }

    public var currency: TrackerCurrency { TrackerCurrency.named(currencyCode) }

    public var formattedRate: String { currency.formatRate(rate) }

    public func earnings(for seconds: TimeInterval) -> Double {
        seconds / 3600 * rate
    }

    public func formattedEarnings(for seconds: TimeInterval, compact: Bool = false) -> String {
        currency.format(earnings(for: seconds), compact: compact)
    }
}

public struct WorkSession: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let projectID: UUID
    public var name: String
    public let createdAt: Date

    public var accumulated: TimeInterval

    public var activeSince: Date?

    public init(
        id: UUID = UUID(),
        projectID: UUID,
        name: String,
        createdAt: Date = Date(),
        accumulated: TimeInterval = 0,
        activeSince: Date? = nil
    ) {
        self.id = id
        self.projectID = projectID
        self.name = name
        self.createdAt = createdAt
        self.accumulated = accumulated
        self.activeSince = activeSince
    }

    public var isRunning: Bool { activeSince != nil }

    public func duration(at now: Date) -> TimeInterval {
        let running = activeSince.map { max(0, now.timeIntervalSince($0)) } ?? 0
        return accumulated + running
    }

    public var dayLabel: String {
        if Calendar.current.isDateInToday(createdAt) { return "Today" }
        if Calendar.current.isDateInYesterday(createdAt) { return "Yesterday" }
        return createdAt.formatted(.dateTime.day().month(.abbreviated))
    }
}

public enum TrackerClock {
    public static func full(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    public static func compact(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d", hours, minutes)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    public static func brief(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    public static func parse(_ text: String) -> TimeInterval? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .replacingOccurrences(of: ",", with: ".")
        guard !trimmed.isEmpty else { return nil }

        if trimmed.contains(":") {
            let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false).map { Double($0) }
            guard parts.count == 2 || parts.count == 3, parts.allSatisfy({ $0 != nil }) else { return nil }
            let hours = parts[0] ?? 0
            let minutes = parts[1] ?? 0
            let seconds = parts.count == 3 ? (parts[2] ?? 0) : 0
            return hours * 3600 + minutes * 60 + seconds
        }

        if trimmed.contains("h") || trimmed.contains("m") {
            var total: TimeInterval = 0
            var number = ""
            for character in trimmed {
                if character.isNumber || character == "." {
                    number.append(character)
                } else if character == "h" {
                    guard let value = Double(number) else { return nil }
                    total += value * 3600
                    number = ""
                } else if character == "m" {
                    guard let value = Double(number) else { return nil }
                    total += value * 60
                    number = ""
                } else if character != " " {
                    return nil
                }
            }
            guard number.isEmpty else { return nil }
            return total
        }

        guard let value = Double(trimmed), value.isFinite, value >= 0 else { return nil }

        return value == value.rounded() ? value * 60 : value * 3600
    }
}
