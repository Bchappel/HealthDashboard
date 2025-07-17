import SwiftUI

struct DashboardView: View {
    @StateObject private var healthManager = HealthManager()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Hello, Braedan")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Spacer()
                        Image(systemName: "person.crop.circle.fill")
                            .resizable()
                            .frame(width: 36, height: 36)
                            .foregroundColor(.blue)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)

                    VStack(spacing: 12) {
                        NavigationLink(destination: WeightHistoryView(healthManager: healthManager)) {
                            HealthRowView(
                                title: "Weight",
                                value: healthManager.latestWeight.map { String(format: "%.1f lbs", $0) } ?? "—",
                                color: .blue
                            )
                        }

                        HealthRowView(
                            title: "Sleep",
                            value: healthManager.latestSleepHours.map { String(format: "%.1f hrs", $0) } ?? "—",
                            color: .indigo
                        )
                        
                        HealthRowView(
                            title: "Calories",
                            value: healthManager.latestCalories.map { String(format: "%.0f kcal", $0) } ?? "—",
                            color: .orange
                        )
                    }

                    .padding(.horizontal)
                }
                .padding(.top)
            }
            .background(Color(.systemGray3))
            .navigationTitle("")
            .navigationBarHidden(true)
        }
    }
}
