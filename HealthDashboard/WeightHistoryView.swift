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

    private var aggregatedWeightData: [DailyWeight] {
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
                return DailyWeight(date: day, averageWeight: avgWeight)
            }
            .sorted { $0.date < $1.date }

        case .halfYear:
            // Group by week (for example, week starting on Saturday)
            var calendarWithSaturdayStart = calendar
            calendarWithSaturdayStart.firstWeekday = 7  // 1=Sunday, 7=Saturday

            let grouped = Dictionary(grouping: samples) { sample in
                calendarWithSaturdayStart.dateInterval(of: .weekOfYear, for: sample.endDate)?.start ?? sample.endDate
            }

            return grouped.map { (weekStart, samples) in
                let avgWeight = samples
                    .map { $0.quantity.doubleValue(for: .pound()) }
                    .reduce(0, +) / Double(samples.count)
                return DailyWeight(date: weekStart, averageWeight: avgWeight)
            }
            .sorted { $0.date < $1.date }
        }
    }

    var yMin: Double {
        guard let minWeight = aggregatedWeightData.min(by: { $0.averageWeight < $1.averageWeight })?.averageWeight else { return 0 }
        return minWeight - 5
    }

    var yMax: Double {
        guard let maxWeight = aggregatedWeightData.max(by: { $0.averageWeight < $1.averageWeight })?.averageWeight else { return 200 }
        return maxWeight + 5
    }

    // Computed stats
    var averageWeight: Double {
        guard !aggregatedWeightData.isEmpty else { return 0 }
        let total = aggregatedWeightData.reduce(0) { $0 + $1.averageWeight }
        return total / Double(aggregatedWeightData.count)
    }

    var minWeight: Double {
        aggregatedWeightData.min(by: { $0.averageWeight < $1.averageWeight })?.averageWeight ?? 0
    }

    var maxWeight: Double {
        aggregatedWeightData.max(by: { $0.averageWeight < $1.averageWeight })?.averageWeight ?? 0
    }

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
                VStack {
                    Text("Min Weight")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(String(format: "%.1f lbs", minWeight))
                        .font(.headline)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 24)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.green.opacity(0.15))
                )
                .frame(maxWidth: .infinity)   // <-- stretch equally
                
                VStack {
                    Text("Avg Weight")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(String(format: "%.1f lbs", averageWeight))
                        .font(.headline)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 24)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.blue.opacity(0.15))
                )
                .frame(maxWidth: .infinity)   // <-- stretch equally

                VStack {
                    Text("Max Weight")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(String(format: "%.1f lbs", maxWeight))
                        .font(.headline)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 24)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.red.opacity(0.15))
                )
                .frame(maxWidth: .infinity)   // <-- stretch equally
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
}
