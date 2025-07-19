import Foundation

struct DailyMetric: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}
