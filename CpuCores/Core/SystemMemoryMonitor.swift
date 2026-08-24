import Combine
import Foundation

struct SystemMemoryReading: Equatable {
    let freeBytes: UInt64
    let activeBytes: UInt64
    let inactiveBytes: UInt64
    let wiredBytes: UInt64
    let usedBytes: UInt64
    let totalBytes: UInt64
    let usedFraction: Double

    var usedPercentage: Int {
        Int((usedFraction * 100).rounded())
    }

    var freeText: String { Self.format(freeBytes) }
    var activeText: String { Self.format(activeBytes) }
    var inactiveText: String { Self.format(inactiveBytes) }
    var wiredText: String { Self.format(wiredBytes) }
    var usedText: String { Self.format(usedBytes) }
    var totalText: String { Self.format(totalBytes) }

    private static func format(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(
            fromByteCount: Int64(bytes),
            countStyle: .memory
        )
    }
}

final class SystemMemoryMonitor: ObservableObject {
    @Published private(set) var reading: SystemMemoryReading?
    @Published private(set) var errorMessage: String?

    func refresh() {
        var sample = CCSystemMemorySample()
        guard CCSystemMemoryTakeSample(&sample) else {
            errorMessage = CCLocalized("error.memory.read")
            return
        }

        reading = SystemMemoryReading(
            freeBytes: sample.freeBytes,
            activeBytes: sample.activeBytes,
            inactiveBytes: sample.inactiveBytes,
            wiredBytes: sample.wiredBytes,
            usedBytes: sample.usedBytes,
            totalBytes: sample.totalBytes,
            usedFraction: min(max(sample.usedFraction, 0), 1)
        )
        errorMessage = nil
    }
}
