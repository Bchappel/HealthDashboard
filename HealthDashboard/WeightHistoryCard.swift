import SwiftUI
import Charts

struct DailyWeight: Identifiable {
    let id = UUID()
    let date: Date
    let averageWeight: Double
}

struct WeightHistoryCard: View {
    let aggregatedWeightData: [DailyWeight]
    let yMin: Double
    let yMax: Double
    let showWeekRangeInLabel: Bool  // <-- NEW PARAMETER

    @State private var selectedDate: Date? = nil
    @State private var selectedWeight: Double? = nil
    @State private var indicatorXPos: CGFloat? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("")
                .font(.headline)
                .foregroundColor(.primary)
                .padding(.top)
                .padding(.horizontal)

            ZStack {
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

                    if let selectedDate = selectedDate {
                        RuleMark(x: .value("Selected Date", selectedDate))
                            .foregroundStyle(Color(white: 0.6)) // neutral gray
                            .lineStyle(StrokeStyle(lineWidth: 1))
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        Rectangle().fill(Color.clear).contentShape(Rectangle())
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        let location = value.location
                                        indicatorXPos = location.x

                                        if let date: Date = proxy.value(atX: location.x) {
                                            if let nearest = aggregatedWeightData.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }) {
                                                selectedDate = nearest.date
                                                selectedWeight = nearest.averageWeight
                                            }
                                        }
                                    }
                                    .onEnded { _ in
                                        selectedDate = nil
                                        selectedWeight = nil
                                        indicatorXPos = nil
                                    }
                            )
                    }
                }
                .chartXAxis {
                    AxisMarks(preset: .aligned, position: .bottom, values: .automatic(desiredCount: 5)) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let dateValue = value.as(Date.self) {
                                Text(dateValue, format: .dateTime.month(.abbreviated).day())
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .chartYScale(domain: yMin...yMax)
                .frame(height: 250)
                .padding([.horizontal, .bottom])

                // Floating label
                if let xPos = indicatorXPos,
                   let date = selectedDate,
                   let weight = selectedWeight {

                    // Calculate labelText here as a local var
                    let labelText = showWeekRangeInLabel
                        ? "\(weekRange(for: date)) • \(String(format: "%.1f lbs", weight))"
                        : "\(date.formatted(.dateTime.month().day())) • \(String(format: "%.1f lbs", weight))"

                    VStack {
                        Text(labelText)
                            .font(.caption)
                            .foregroundColor(.primary)
                            .padding(8)
                            .background(.ultraThinMaterial)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                            )
                            .fixedSize()
                            .frame(minWidth: 100)
                            .clipped()
                            .animation(nil, value: weight)
                    }
                    .position(x: clamp(xPos, min: 50, max: UIScreen.main.bounds.width - 50), y: 30)
                    .animation(.easeInOut(duration: 0.1), value: xPos)
                }

            }
            .frame(height: 250)
            .padding(.bottom, 10)
        }
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 4)
        .padding(.horizontal)
    }

    // MARK: - Helper Functions

    func weekRange(for date: Date) -> String {
        let calendar = Calendar.current
        var customCalendar = calendar
        customCalendar.firstWeekday = 7 // Saturday as start of week

        guard let weekStart = customCalendar.dateInterval(of: .weekOfYear, for: date)?.start else {
            return date.formatted(.dateTime.month().day())
        }

        let weekEnd = customCalendar.date(byAdding: .day, value: 6, to: weekStart) ?? date

        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"

        return "\(formatter.string(from: weekStart)) – \(formatter.string(from: weekEnd))"
    }

    func clamp(_ value: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        if value < min { return min }
        if value > max { return max }
        return value
    }
}
