import SwiftUI
import Charts
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

struct DailyWeight: Identifiable {
    let id = UUID()
    let date: Date
    let averageWeight: Double
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
            // Group by day
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
            // Group by week (start of week)
            let grouped = Dictionary(grouping: samples) { sample in
                calendar.dateInterval(of: .weekOfYear, for: sample.endDate)?.start ?? sample.endDate
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

    var xAxisValues: [Date] {

        switch selectedRange {
        case .week:
            return aggregatedWeightData.map { $0.date }
        case .month:
            return stride(from: 0, to: aggregatedWeightData.count, by: 3).compactMap {
                aggregatedWeightData.indices.contains($0) ? aggregatedWeightData[$0].date : nil
            }
        case .halfYear:
            return aggregatedWeightData.map { $0.date }
        }
    }

    // Computed stats:
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
            // Chart near top
            Chart {
                ForEach(aggregatedWeightData) { entry in
                    LineMark(
                        x: .value("Date", entry.date),
                        y: .value("Weight (lbs)", entry.averageWeight)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.blue)
                    .symbol(Circle())
                }
            }
            .chartXAxis {
                AxisMarks(values: xAxisValues) { value in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.day().month())
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .chartYScale(domain: yMin...yMax)
            .frame(height: 300)
            .padding(.horizontal)

            // Stats in middle
            HStack(spacing: 24) {
                VStack {
                    Text("Avg Weight")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(String(format: "%.1f lbs", averageWeight))
                        .font(.headline)
                }
                VStack {
                    Text("Min Weight")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(String(format: "%.1f lbs", minWeight))
                        .font(.headline)
                }
                VStack {
                    Text("Max Weight")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(String(format: "%.1f lbs", maxWeight))
                        .font(.headline)
                }
            }
            .padding()
            .frame(maxWidth: .infinity)

            Spacer()

            // Picker tabs pinned at bottom
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
