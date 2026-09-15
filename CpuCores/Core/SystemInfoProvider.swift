//
//  SystemInfoProvider.swift
//  CpuCores
//
//  Created by Lampadina_17 on 30/12/23.
//

import Foundation
import Darwin
import UIKit

struct DeviceHardwareInfo: Equatable {
    let deviceFamily: String
    let modelIdentifier: String
    let boardIdentifier: String
    let operatingSystem: String
    let architecture: String
    let logicalCoreCount: Int
    let activeCoreCount: Int
    let physicalMemory: String
    let memoryPageSize: String
    let storageCapacity: String
    let storageAvailable: String
    let nativeResolution: String
    let logicalResolution: String
    let displayScale: String
    let maximumRefreshRate: String
    let batteryLevel: String
    let batteryState: String
    let batteryHealth: String
    let batteryWear: String
    let batteryMaximumCapacity: String
    let batteryDesignCapacity: String
    let batteryCycleCount: String
    let thermalState: String
    let lowPowerMode: String

    static func current(diskStatus: DiskStatus? = DiskStatus.current()) -> DeviceHardwareInfo {
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true

        let processInfo = ProcessInfo.processInfo
        let screen = UIScreen.main
        let nativeSize = normalized(screen.nativeBounds.size)
        let logicalSize = normalized(screen.bounds.size)
        let batteryPercentage = device.batteryLevel >= 0
            ? CCFormatted("hardware.battery.value_format", Int((device.batteryLevel * 100).rounded()))
            : CCLocalized("common.unavailable")
        let batteryHealth = batteryHealthDetails()

        return DeviceHardwareInfo(
            deviceFamily: device.localizedModel,
            modelIdentifier: modelIdentifier(),
            boardIdentifier: sysctlString("hw.model") ?? CCLocalized("common.unavailable"),
            operatingSystem: "\(device.systemName) \(device.systemVersion)",
            architecture: architectureName,
            logicalCoreCount: processInfo.processorCount,
            activeCoreCount: processInfo.activeProcessorCount,
            physicalMemory: formattedBytes(processInfo.physicalMemory, style: .memory),
            memoryPageSize: formattedBytes(UInt64(getpagesize()), style: .memory),
            storageCapacity: diskStatus?.totalText ?? CCLocalized("common.unavailable"),
            storageAvailable: diskStatus?.freeText ?? CCLocalized("common.unavailable"),
            nativeResolution: CCFormatted(
                "hardware.display.resolution_format",
                Int(nativeSize.width.rounded()),
                Int(nativeSize.height.rounded())
            ),
            logicalResolution: CCFormatted(
                "hardware.display.logical_format",
                Int(logicalSize.width.rounded()),
                Int(logicalSize.height.rounded())
            ),
            displayScale: CCFormatted("hardware.display.scale_format", Double(screen.nativeScale)),
            maximumRefreshRate: CCFormatted("hardware.display.refresh_format", screen.maximumFramesPerSecond),
            batteryLevel: batteryPercentage,
            batteryState: batteryStateText(device.batteryState),
            batteryHealth: batteryHealth.health,
            batteryWear: batteryHealth.wear,
            batteryMaximumCapacity: batteryHealth.maximumCapacity,
            batteryDesignCapacity: batteryHealth.designCapacity,
            batteryCycleCount: batteryHealth.cycleCount,
            thermalState: thermalStateText(processInfo.thermalState),
            lowPowerMode: CCLocalized(processInfo.isLowPowerModeEnabled ? "hardware.state.enabled" : "hardware.state.disabled")
        )
    }

    private static func normalized(_ size: CGSize) -> CGSize {
        CGSize(width: min(size.width, size.height), height: max(size.width, size.height))
    }

    private static func modelIdentifier() -> String {
        if let simulatedModel = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"],
           !simulatedModel.isEmpty {
            return simulatedModel
        }

        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        return mirror.children.reduce(into: "") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            identifier.append(Character(UnicodeScalar(UInt8(value))))
        }
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 1 else { return nil }

        var value = [CChar](repeating: 0, count: size)
        let result = value.withUnsafeMutableBufferPointer { buffer in
            sysctlbyname(name, buffer.baseAddress, &size, nil, 0)
        }
        guard result == 0 else { return nil }
        return String(cString: value)
    }

    private static var architectureName: String {
        #if arch(arm64)
        return "ARM64"
        #elseif arch(x86_64)
        return "x86_64"
        #elseif arch(arm)
        return "ARM"
        #else
        return CCLocalized("common.unavailable")
        #endif
    }

    private static func formattedBytes(_ bytes: UInt64, style: ByteCountFormatter.CountStyle) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: style)
    }

    private static func batteryStateText(_ state: UIDevice.BatteryState) -> String {
        switch state {
        case .unplugged:
            return CCLocalized("hardware.battery.unplugged")
        case .charging:
            return CCLocalized("hardware.battery.charging")
        case .full:
            return CCLocalized("hardware.battery.full")
        case .unknown:
            fallthrough
        @unknown default:
            return CCLocalized("common.unavailable")
        }
    }

    private static func batteryHealthDetails() -> BatteryHealthDetails {
        let unavailable = CCLocalized("common.unavailable")

        #if CPUCORES_TROLLSTORE
        var sample = CCBatteryHealthSample()
        guard CCBatteryHealthTakeSample(&sample) else {
            return BatteryHealthDetails(
                health: unavailable,
                wear: unavailable,
                maximumCapacity: unavailable,
                designCapacity: unavailable,
                cycleCount: unavailable
            )
        }

        let healthPercentage: Int? = sample.hasHealthFraction
            ? Int((min(max(sample.healthFraction, 0), 1) * 100).rounded())
            : nil

        return BatteryHealthDetails(
            health: healthPercentage.map { CCFormatted("hardware.battery.value_format", $0) } ?? unavailable,
            wear: healthPercentage.map { CCFormatted("hardware.battery.value_format", 100 - $0) } ?? unavailable,
            maximumCapacity: sample.hasMaximumCapacity
                ? CCFormatted("hardware.battery.capacity_format", sample.maximumCapacity)
                : unavailable,
            designCapacity: sample.hasDesignCapacity
                ? CCFormatted("hardware.battery.capacity_format", sample.designCapacity)
                : unavailable,
            cycleCount: sample.hasCycleCount ? String(sample.cycleCount) : unavailable
        )
        #else
        return BatteryHealthDetails(
            health: unavailable,
            wear: unavailable,
            maximumCapacity: unavailable,
            designCapacity: unavailable,
            cycleCount: unavailable
        )
        #endif
    }

    private static func thermalStateText(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal:
            return CCLocalized("hardware.thermal.nominal")
        case .fair:
            return CCLocalized("hardware.thermal.fair")
        case .serious:
            return CCLocalized("hardware.thermal.serious")
        case .critical:
            return CCLocalized("hardware.thermal.critical")
        @unknown default:
            return CCLocalized("common.unavailable")
        }
    }
}

private struct BatteryHealthDetails {
    let health: String
    let wear: String
    let maximumCapacity: String
    let designCapacity: String
    let cycleCount: String
}

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
