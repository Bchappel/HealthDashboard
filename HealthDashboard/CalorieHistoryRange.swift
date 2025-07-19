enum CalorieHistoryRange: String, CaseIterable, Identifiable {
    case week = "Week"
    case month = "Month"
    case halfYear = "6 Months"

    var id: String { rawValue }

    var days: Int {
        switch self {
        case .week: return 7
        case .month: return 30
        case .halfYear: return 180
        }
    }
}
