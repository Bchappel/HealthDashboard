import SwiftUI
import HealthKit

enum WeightHistoryRange: String, CaseIterable, Identifiable {
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

struct WeightHistoryView: View {
    @ObservedObject var healthManager: HealthManager
    @State private var selectedRange: WeightHistoryRange = .month

    // MARK: - Aggregation logic

    private var aggregatedWeightData: [DailyMetric] {
        let calendar = Calendar.current
        let samples = healthManager.weightHistory

        switch selectedRange {
        case .week, .month:
            // Group by day (start of day)
            let grouped = Dictionary(grouping: samples) { sample in
                calendar.startOfDay(for: sample.endDate)
            }
            return grouped.map { (day, samples) in
                let avgWeight = samples
                    .map { $0.quantity.doubleValue(for: .pound()) }
                    .reduce(0, +) / Double(samples.count)
                return DailyMetric(date: day, value: avgWeight)
            }
            .sorted { $0.date < $1.date }

        case .halfYear:
            // Group by week (start on Saturday)
            var calendarWithSaturdayStart = calendar
            calendarWithSaturdayStart.firstWeekday = 7

            let grouped = Dictionary(grouping: samples) { sample in
                calendarWithSaturdayStart.dateInterval(of: .weekOfYear, for: sample.endDate)?.start ?? sample.endDate
            }

            return grouped.map { (weekStart, samples) in
                let avgWeight = samples
                    .map { $0.quantity.doubleValue(for: .pound()) }
                    .reduce(0, +) / Double(samples.count)
                return DailyMetric(date: weekStart, value: avgWeight)
            }
            .sorted { $0.date < $1.date }
        }
    }

    // MARK: - Y Axis Bounds

    var yMin: Double {
        guard let min = aggregatedWeightData.min(by: { $0.value < $1.value })?.value else { return 0 }
        return min - 5
    }

    var yMax: Double {
        guard let max = aggregatedWeightData.max(by: { $0.value < $1.value })?.value else { return 200 }
        return max + 5
    }

    // MARK: - Computed Stats

    var averageWeight: Double {
        guard !aggregatedWeightData.isEmpty else { return 0 }
        let total = aggregatedWeightData.reduce(0) { $0 + $1.value }
        return total / Double(aggregatedWeightData.count)
    }

    var minWeight: Double {
        aggregatedWeightData.min(by: { $0.value < $1.value })?.value ?? 0
    }

    var maxWeight: Double {
        aggregatedWeightData.max(by: { $0.value < $1.value })?.value ?? 0
    }

    // MARK: - Body

    var body: some View {
        VStack {
            // Chart card
            WeightHistoryCard(
                aggregatedWeightData: aggregatedWeightData,
                yMin: yMin,
                yMax: yMax,
                showWeekRangeInLabel: selectedRange == .halfYear
            )
            .padding(.top, 16)

            // Stats section
            HStack(spacing: 4) {
                statView(title: "Min Weight", value: minWeight, color: .green)
                statView(title: "Avg Weight", value: averageWeight, color: .blue)
                statView(title: "Max Weight", value: maxWeight, color: .red)
            }
            .padding(.horizontal)
            .frame(maxWidth: .infinity)

            Spacer()

            // Range picker
            Picker("Range", selection: $selectedRange) {
                ForEach(WeightHistoryRange.allCases) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .padding()
        }
        .navigationTitle("Weight History")
        .onAppear {
            healthManager.fetchWeightHistory(days: selectedRange.days)
        }
        .onChange(of: selectedRange) { _, newRange in
            healthManager.fetchWeightHistory(days: newRange.days)
        }
    }

    // MARK: - Helper View

    private func statView(title: String, value: Double, color: Color) -> some View {
        VStack {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(String(format: "%.1f lbs", value))
                .font(.headline)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 24)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(0.15))
        )
        .frame(maxWidth: .infinity)
    }
}
