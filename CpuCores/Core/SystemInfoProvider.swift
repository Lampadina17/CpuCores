//
//  SystemInfoProvider.swift
//  CpuCores
//
//  Created by Lampadina_17 on 30/12/23.
//

import Foundation
import Darwin

struct SystemCPUSummary {
    let coreLoads: [Double]
    let overallLoad: Double
}

struct SystemMemorySummary {
    let usedBytes: UInt64
    let totalBytes: UInt64
    let usedFraction: Double

    var usedText: String {
        ByteCountFormatter.string(
            fromByteCount: Int64(usedBytes),
            countStyle: .memory
        )
    }

    var totalText: String {
        ByteCountFormatter.string(
            fromByteCount: Int64(totalBytes),
            countStyle: .memory
        )
    }

    var displayText: String {
        CCFormatted("summary.used_format", usedText, totalText)
    }
}

struct SystemInfoProvider {
    // Widget extensions are short-lived, so obtain a baseline and a second
    // sample in the same invocation instead of returning the lifetime average.
    func systemCPU(maxCores: Int = 8) -> SystemCPUSummary? {
        guard let sampler = CPUMulticoreSamplerCreate() else {
            return nil
        }
        defer { CPUMulticoreSamplerDestroy(sampler) }

        let requestedCoreCount = min(max(maxCores, 1), 8)
        var loads = [Float](repeating: 0, count: requestedCoreCount)
        var sampledCoreCount: UInt32 = 0
        var overallLoad: Float = 0
        let didSample = loads.withUnsafeMutableBufferPointer { buffer in
            CPUMulticoreSamplerTakeIntervalSample(
                sampler,
                buffer.baseAddress,
                UInt32(buffer.count),
                &sampledCoreCount,
                &overallLoad,
                250_000
            )
        }

        guard didSample, sampledCoreCount > 0 else { return nil }

        let count = min(Int(sampledCoreCount), loads.count)
        let coreLoads = loads.prefix(count).map {
            min(max(Double($0), 0), 1)
        }
        return SystemCPUSummary(
            coreLoads: coreLoads,
            overallLoad: min(max(Double(overallLoad), 0), 1)
        )
    }

    func systemCPUUsage() -> Double {
        (systemCPU()?.overallLoad ?? 0) * 100
    }

    func systemMemory() -> SystemMemorySummary? {
        var sample = CCSystemMemorySample()
        guard CCSystemMemoryTakeSample(&sample) else { return nil }

        return SystemMemorySummary(
            usedBytes: sample.usedBytes,
            totalBytes: sample.totalBytes,
            usedFraction: min(max(sample.usedFraction, 0), 1)
        )
    }

    func displayDisk() -> String {
        DiskStatus.current()?.displayText ?? CCLocalized("common.unavailable")
    }

    func displayUptime() -> String {
        if let bootTime = bootTime() {
            let calendar = Calendar.current
            let now = Date()
            let components = calendar.dateComponents([.day, .hour, .minute], from: bootTime, to: now)
            if let days = components.day, let hours = components.hour, let minutes = components.minute {
                return CCFormatted("uptime.format", days, hours, minutes)
            }
        }
        return ""
    }

    func bootTime() -> Date? {
        var tv = timeval()
        var tvSize = MemoryLayout<timeval>.size
        let err = sysctlbyname("kern.boottime", &tv, &tvSize, nil, 0)
        guard err == 0, tvSize == MemoryLayout<timeval>.size else {
            return nil
        }
        return Date(timeIntervalSince1970: Double(tv.tv_sec) + Double(tv.tv_usec) / 1_000_000.0)
    }
}
