import Foundation
import HealthKit

class HealthManager: ObservableObject {
    private let healthStore = HKHealthStore()

    @Published var latestWeight: Double?
    @Published var latestSleepHours: Double?
    @Published var weightHistory: [HKQuantitySample] = []
    @Published var latestCalories: Double?   // <-- New published property

    init() {
        requestAuthorization()
    }

    private func requestAuthorization() {
        let typesToRead: Set = [
            HKObjectType.quantityType(forIdentifier: .bodyMass)!,
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .basalEnergyBurned)!
        ]

        healthStore.requestAuthorization(toShare: [], read: typesToRead) { success, error in
            if success {
                self.fetchLatestWeight()
                self.fetchLatestSleep()
                self.fetchTotalCaloriesToday()  // <-- Fetch total calories on success
            } else {
                print("Authorization failed: \(error?.localizedDescription ?? "Unknown error")")
            }
        }
    }

    private func fetchLatestWeight() {
        guard let weightType = HKQuantityType.quantityType(forIdentifier: .bodyMass) else { return }

        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let query = HKSampleQuery(
            sampleType: weightType,
            predicate: nil,
            limit: 1,
            sortDescriptors: [sort]
        ) { _, samples, _ in
            guard let sample = samples?.first as? HKQuantitySample else { return }
            let lbs = sample.quantity.doubleValue(for: .pound())

            DispatchQueue.main.async {
                self.latestWeight = lbs
            }
        }

        healthStore.execute(query)
    }

    func fetchWeightHistory(days: Int = 30) {
        guard let weightType = HKQuantityType.quantityType(forIdentifier: .bodyMass) else { return }

        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: Date())
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)

        let query = HKSampleQuery(sampleType: weightType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, error in
            guard let samples = samples as? [HKQuantitySample], error == nil else {
                print("Weight history query error: \(error?.localizedDescription ?? "Unknown error")")
                return
            }

            DispatchQueue.main.async {
                self.weightHistory = samples
            }
        }

        healthStore.execute(query)
    }

    private func fetchLatestSleep() {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return }

        let now = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -2, to: now)! // last 2 days

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: now, options: [])

        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        let query = HKSampleQuery(
            sampleType: sleepType,
            predicate: predicate,
            limit: 0,
            sortDescriptors: [sort]
        ) { _, samples, error in

            if let error = error {
                print("Sleep query error: \(error.localizedDescription)")
                return
            }

            let asleepValue: Int

            if #available(iOS 16, *) {
                asleepValue = HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
            } else {
                asleepValue = HKCategoryValueSleepAnalysis.asleep.rawValue
            }

            guard let samples = samples as? [HKCategorySample] else {
                print("No sleep samples found")
                return
            }

            // Filter only the 'asleep' samples
            let asleepSamples = samples.filter { $0.value == asleepValue }

            // Get the most recent asleep sample (they are sorted descending)
            guard let latestSleepSample = asleepSamples.first else {
                DispatchQueue.main.async {
                    self.latestSleepHours = nil
                }
                return
            }

            // Calculate duration in hours for that sample
            let duration = latestSleepSample.endDate.timeIntervalSince(latestSleepSample.startDate) / 3600

            DispatchQueue.main.async {
                self.latestSleepHours = duration
            }
        }

        healthStore.execute(query)
    }

    // MARK: - New: Fetch total calories burned today (basal + active)

    func fetchTotalCaloriesToday() {
        guard
            let basalType = HKQuantityType.quantityType(forIdentifier: .basalEnergyBurned),
            let activeType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)
        else { return }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let now = Date()
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: [])

        let dispatchGroup = DispatchGroup()

        var basalTotal = 0.0
        var activeTotal = 0.0

        func fetchSum(for type: HKQuantityType, completion: @escaping (Double) -> Void) {
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, error in
                guard error == nil else {
                    print("Error fetching \(type.identifier): \(error!.localizedDescription)")
                    completion(0)
                    return
                }
                let sum = result?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                completion(sum)
            }
            healthStore.execute(query)
        }

        dispatchGroup.enter()
        fetchSum(for: basalType) { sum in
            basalTotal = sum
            dispatchGroup.leave()
        }

        dispatchGroup.enter()
        fetchSum(for: activeType) { sum in
            activeTotal = sum
            dispatchGroup.leave()
        }

        dispatchGroup.notify(queue: .main) {
            let totalCalories = basalTotal + activeTotal
            print("Total calories burned today: \(totalCalories) kcal")
            DispatchQueue.main.async {
                self.latestCalories = totalCalories
            }
        }
    }
}
