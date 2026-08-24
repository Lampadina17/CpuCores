import Foundation

struct DiskStatus {
    let totalBytes: UInt64
    let freeBytes: UInt64
    let usedBytes: UInt64
    let usedFraction: Double

    var totalText: String { Self.formatted(totalBytes) }
    var freeText: String { Self.formatted(freeBytes) }
    var usedText: String { Self.formatted(usedBytes) }

    var displayText: String {
        CCFormatted("summary.used_format", usedText, totalText)
    }

    static func current() -> DiskStatus? {
        var sample = CCDiskSample()
        let didSample = NSHomeDirectory().withCString { path in
            CCDiskTakeSample(path, &sample)
        }

        guard didSample else { return nil }
        return DiskStatus(
            totalBytes: sample.totalBytes,
            freeBytes: sample.freeBytes,
            usedBytes: sample.usedBytes,
            usedFraction: min(max(sample.usedFraction, 0), 1)
        )
    }

    private static func formatted(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(
            fromByteCount: Int64(clamping: bytes),
            countStyle: .file
        )
    }
}
