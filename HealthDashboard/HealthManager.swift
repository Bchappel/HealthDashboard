import Foundation
import HealthKit

class HealthManager: ObservableObject {
    private let healthStore = HKHealthStore()

    @Published var latestWeight: Double?
    @Published var latestSleepHours: Double?
    @Published var weightHistory: [HKQuantitySample] = []
    
    @Published var totalCaloriesHistory: [DailyMetric] = []  // Total calories burned per day

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
                self.fetchTotalCalories(days: 30)
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
        let startDate = Calendar.current.date(byAdding: .day, value: -2, to: now)!

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

            let asleepSamples = samples.filter { $0.value == asleepValue }

            guard let latestSleepSample = asleepSamples.first else {
                DispatchQueue.main.async {
                    self.latestSleepHours = nil
                }
                return
            }

            let duration = latestSleepSample.endDate.timeIntervalSince(latestSleepSample.startDate) / 3600

            DispatchQueue.main.async {
                self.latestSleepHours = duration
            }
        }

        healthStore.execute(query)
    }

    func fetchTotalCalories(days: Int = 30) {
        guard
            let activeEnergyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned),
            let basalEnergyType = HKQuantityType.quantityType(forIdentifier: .basalEnergyBurned)
        else { return }

        let calendar = Calendar.current
        let startDate = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -days, to: Date())!)
        let endDate = Date()

        let interval = DateComponents(day: 1)

        func createQuery(for type: HKQuantityType, completion: @escaping ([HKStatistics]) -> Void) -> HKStatisticsCollectionQuery {
            let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: startDate,
                intervalComponents: interval
            )
            query.initialResultsHandler = { _, results, error in
                if let error = error {
                    print("Error fetching \(type.identifier): \(error.localizedDescription)")
                    completion([])
                    return
                }

                var statsArray = [HKStatistics]()
                results?.enumerateStatistics(from: startDate, to: endDate) { statistics, _ in
                    statsArray.append(statistics)
                }
                completion(statsArray)
            }
            return query
        }

        let dispatchGroup = DispatchGroup()

        var basalStats: [HKStatistics] = []
        var activeStats: [HKStatistics] = []

        dispatchGroup.enter()
        let basalQuery = createQuery(for: basalEnergyType) { stats in
            basalStats = stats
            dispatchGroup.leave()
        }

        dispatchGroup.enter()
        let activeQuery = createQuery(for: activeEnergyType) { stats in
            activeStats = stats
            dispatchGroup.leave()
        }

        healthStore.execute(basalQuery)
        healthStore.execute(activeQuery)

        dispatchGroup.notify(queue: .main) {
            var combinedCalories = [DailyMetric]()

            let basalByDate = Dictionary(uniqueKeysWithValues: basalStats.compactMap { stat -> (Date, Double)? in
                guard let sum = stat.sumQuantity() else { return nil }
                return (stat.startDate, sum.doubleValue(for: .kilocalorie()))
            })

            let activeByDate = Dictionary(uniqueKeysWithValues: activeStats.compactMap { stat -> (Date, Double)? in
                guard let sum = stat.sumQuantity() else { return nil }
                return (stat.startDate, sum.doubleValue(for: .kilocalorie()))
            })

            let allDates = Set(basalByDate.keys).union(activeByDate.keys)

            for date in allDates.sorted() {
                let basalValue = basalByDate[date] ?? 0
                let activeValue = activeByDate[date] ?? 0
                let total = basalValue + activeValue
                combinedCalories.append(DailyMetric(date: date, value: total))
            }

            self.totalCaloriesHistory = combinedCalories
        }
    }

    // MARK: - Computed Properties

    var latestTotalCalories: Double? {
        totalCaloriesHistory.last?.value
    }
}
