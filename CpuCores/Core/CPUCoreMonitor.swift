import Combine
import Foundation

struct CPUCoreReading: Identifiable, Equatable {
    let id: Int
    let load: Double

    var percentage: Int {
        Int((load * 100.0).rounded())
    }
}

final class CPUCoreMonitor: ObservableObject {
    @Published private(set) var cores: [CPUCoreReading] = []
    @Published private(set) var overallLoad: Double = 0
    @Published private(set) var errorMessage: String?

    private let maximumCoreCount = 8
    private var sampler: CPUMulticoreSamplerRef?
    private var timer: Timer?

    init() {
        sampler = CPUMulticoreSamplerCreate()
        if sampler == nil {
            errorMessage = CCLocalized("error.cpu.initialize")
        }
    }

    deinit {
        timer?.invalidate()
        if let sampler {
            CPUMulticoreSamplerDestroy(sampler)
        }
    }

    func start() {
        guard timer == nil, let sampler else { return }

        CPUMulticoreSamplerReset(sampler)
        takeSample()

        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.takeSample()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func takeSample() {
        guard let sampler else { return }

        var loads = [Float](repeating: 0, count: maximumCoreCount)
        var sampledCoreCount: UInt32 = 0
        var overallLoad: Float = 0

        let didSample = loads.withUnsafeMutableBufferPointer { buffer in
            CPUMulticoreSamplerTakeSample(
                sampler,
                buffer.baseAddress,
                UInt32(buffer.count),
                &sampledCoreCount,
                &overallLoad
            )
        }

        guard didSample else {
            errorMessage = CCLocalized("error.cpu.read")
            return
        }

        let count = min(Int(sampledCoreCount), loads.count)
        cores = (0..<count).map { index in
            CPUCoreReading(
                id: index,
                load: min(max(Double(loads[index]), 0), 1)
            )
        }
        self.overallLoad = min(max(Double(overallLoad), 0), 1)
        errorMessage = nil
    }
}
