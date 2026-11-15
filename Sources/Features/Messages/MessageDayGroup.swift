import Foundation

/// The messages of one calendar day, oldest first, for the timeline's section headers.
struct MessageDayGroup: Identifiable, Hashable, Sendable {
    let day: Date
    let messages: [HiveMessage]
    var id: Date { day }

    /// Groups messages by calendar day. Days and messages are both in ascending order.
    static func groups(from messages: [HiveMessage], calendar: Calendar = .current) -> [MessageDayGroup] {
        let byDay = Dictionary(grouping: messages) { calendar.startOfDay(for: $0.createdAt) }
        return byDay.keys.sorted().map { day in
            MessageDayGroup(day: day, messages: (byDay[day] ?? []).sorted { $0.seq < $1.seq })
        }
    }
}
