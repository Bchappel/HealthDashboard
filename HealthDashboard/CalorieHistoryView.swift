import SwiftUI
import HealthKit

struct CalorieHistoryView: View {
    @ObservedObject var healthManager: HealthManager
    @State private var selectedRange: CalorieHistoryRange = .month

    // MARK: - Aggregation Logic

    private var aggregatedCalorieData: [DailyMetric] {
        let calendar = Calendar.current

        let samples = healthManager.totalCaloriesHistory

        switch selectedRange {
        case .week, .month:
            // Group by day
            let grouped = Dictionary(grouping: samples) { sample in
                calendar.startOfDay(for: sample.date)
            }
            return grouped.map { (day, samples) in
                let totalCalories = samples.map { $0.value }.reduce(0, +)
                return DailyMetric(date: day, value: totalCalories)
            }
            .sorted { $0.date < $1.date }

        case .halfYear:
            // Group by week
            var customCalendar = calendar
            customCalendar.firstWeekday = 7  // Saturday start

            let grouped = Dictionary(grouping: samples) { sample in
                customCalendar.dateInterval(of: .weekOfYear, for: sample.date)?.start ?? sample.date
            }
            return grouped.map { (weekStart, samples) in
                let totalCalories = samples.map { $0.value }.reduce(0, +)
                return DailyMetric(date: weekStart, value: totalCalories)
            }
            .sorted { $0.date < $1.date }
        }
    }

    var yMin: Double {
        guard let min = aggregatedCalorieData.min(by: { $0.value < $1.value })?.value else { return 0 }
        return min - 50
    }

    var yMax: Double {
        guard let max = aggregatedCalorieData.max(by: { $0.value < $1.value })?.value else { return 3000 }
        return max + 50
    }

    // MARK: - View

    var body: some View {
        VStack {
            CalorieHistoryCard(
                aggregatedCalorieData: aggregatedCalorieData,
                yMin: yMin,
                yMax: yMax,
                showWeekRangeInLabel: selectedRange == .halfYear
            )
            .padding(.top, 16)

            // Range Picker
            Picker("Range", selection: $selectedRange) {
                ForEach(CalorieHistoryRange.allCases) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            Spacer()
        }
        .navigationTitle("Calories Burned")
        .onAppear {
            healthManager.fetchTotalCalories(days: selectedRange.days)
        }
        .onChange(of: selectedRange) { _, newRange in
            healthManager.fetchTotalCalories(days: newRange.days)
        }
    }
}
