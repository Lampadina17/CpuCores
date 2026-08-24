//
//  CardView.swift
//  CpuCores
//
//  Created by Lampadina_17 on 05/10/22.
//

import SwiftUI

struct SystemBackground: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.025, green: 0.035, blue: 0.11),
                        Color(red: 0.085, green: 0.055, blue: 0.19),
                        Color(red: 0.025, green: 0.105, blue: 0.16)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                RadialGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.46, green: 0.24, blue: 0.95).opacity(0.28),
                        Color.clear
                    ]),
                    center: UnitPoint(x: 0.86, y: 0.08),
                    startRadius: 0,
                    endRadius: max(proxy.size.width, proxy.size.height) * 0.62
                )

                RadialGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.08, green: 0.78, blue: 0.82).opacity(0.16),
                        Color.clear
                    ]),
                    center: UnitPoint(x: 0.10, y: 0.92),
                    startRadius: 0,
                    endRadius: max(proxy.size.width, proxy.size.height) * 0.58
                )

                RadialGradient(
                    gradient: Gradient(colors: [
                        Color(red: 1.0, green: 0.40, blue: 0.12).opacity(0.09),
                        Color.clear
                    ]),
                    center: UnitPoint(x: 0.92, y: 0.88),
                    startRadius: 0,
                    endRadius: max(proxy.size.width, proxy.size.height) * 0.38
                )
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

struct CPUStatsBlock: View {
    let cores: [CPUCoreReading]
    let overallLoad: Double
    let errorMessage: String?
    let usesGroupedLayout: Bool

    init(
        cores: [CPUCoreReading],
        overallLoad: Double,
        errorMessage: String?,
        usesGroupedLayout: Bool = false
    ) {
        self.cores = cores
        self.overallLoad = overallLoad
        self.errorMessage = errorMessage
        self.usesGroupedLayout = usesGroupedLayout
    }

    private var percentage: Int {
        Int((overallLoad * 100).rounded())
    }

    var body: some View {
        GlassBlock {
            VStack(alignment: .leading, spacing: 18) {
                SectionHeader(
                    title: CCLocalized("metric.cpu.title"),
                    subtitle: CCLocalized("metric.cpu.subtitle"),
                    icon: "cpu",
                    value: "\(percentage)%",
                    accent: Color(red: 0.24, green: 0.84, blue: 1.0)
                )

                HorizontalProgressBar(
                    value: overallLoad,
                    color: Color(red: 0.24, green: 0.84, blue: 1.0)
                )

                if let errorMessage {
                    UnavailableRow(message: errorMessage)
                } else if cores.isEmpty {
                    LoadingRow(message: CCLocalized("loading.cpu"))
                } else {
                    Divider()
                        .background(Color.white.opacity(0.10))

                    if usesGroupedLayout {
                        HStack(alignment: .top, spacing: 14) {
                            coreGroup(
                                Array(visibleCores.prefix(firstGroupCount)),
                                title: groupTitle(from: visibleCores.first, to: visibleCores[safe: firstGroupCount - 1])
                            )

                            coreGroup(
                                Array(visibleCores.dropFirst(firstGroupCount)),
                                title: groupTitle(from: visibleCores[safe: firstGroupCount], to: visibleCores.last)
                            )
                        }
                    } else {
                        VStack(spacing: 12) {
                            ForEach(visibleCores) { core in
                                coreRow(core)
                            }
                        }
                    }
                }
            }
        }
    }

    private var visibleCores: [CPUCoreReading] {
        Array(cores.prefix(8))
    }

    private var firstGroupCount: Int {
        (visibleCores.count + 1) / 2
    }

    private func coreGroup(_ readings: [CPUCoreReading], title: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.50))

            ForEach(readings) { core in
                coreRow(core)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.065), lineWidth: 1)
        )
    }

    private func coreRow(_ core: CPUCoreReading) -> some View {
        MetricProgressRow(
            title: CCFormatted("metric.core.format", core.id + 1),
            value: core.load,
            valueText: "\(core.percentage)%",
            color: coreColor(for: core.load)
        )
    }

    private func groupTitle(from first: CPUCoreReading?, to last: CPUCoreReading?) -> String {
        guard let first, let last else { return CCLocalized("metric.core.group") }
        return CCFormatted("metric.core.range_format", first.id + 1, last.id + 1)
    }

    private func coreColor(for load: Double) -> Color {
        if load >= 0.80 {
            return Color(red: 1.0, green: 0.33, blue: 0.42)
        }
        if load >= 0.55 {
            return Color(red: 1.0, green: 0.72, blue: 0.27)
        }
        return Color(red: 0.27, green: 0.96, blue: 0.82)
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

struct MemoryStatsBlock: View {
    let reading: SystemMemoryReading?
    let errorMessage: String?
    @ObservedObject var cleaner: SystemCleanerService

    var body: some View {
        GlassBlock {
            VStack(alignment: .leading, spacing: 18) {
                SectionHeader(
                    title: CCLocalized("metric.ram.title"),
                    subtitle: CCLocalized("metric.ram.subtitle"),
                    icon: "memorychip",
                    value: reading.map { "\($0.usedPercentage)%" } ?? "—",
                    accent: Color(red: 0.78, green: 0.48, blue: 1.0)
                )

                HorizontalProgressBar(
                    value: reading?.usedFraction ?? 0,
                    color: Color(red: 0.78, green: 0.48, blue: 1.0)
                )

                if let errorMessage {
                    UnavailableRow(message: errorMessage)
                } else if let reading {
                    HStack(spacing: 10) {
                        ValueLabel(title: CCLocalized("memory.used"), value: reading.usedText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ValueLabel(title: CCLocalized("memory.total"), value: reading.totalText, alignment: .trailing)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }

                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        spacing: 10
                    ) {
                        DetailTile(title: CCLocalized("memory.free"), value: reading.freeText)
                        DetailTile(title: CCLocalized("memory.active"), value: reading.activeText)
                        DetailTile(title: CCLocalized("memory.inactive"), value: reading.inactiveText)
                        DetailTile(title: CCLocalized("memory.wired"), value: reading.wiredText)
                    }
                } else {
                    LoadingRow(message: CCLocalized("loading.memory"))
                }

                CleanerActionControl(cleaner: cleaner, action: .ram)
            }
        }
    }
}

struct DiskStatsBlock: View {
    let status: DiskStatus?
    @ObservedObject var cleaner: SystemCleanerService

    var body: some View {
        GlassBlock {
            VStack(alignment: .leading, spacing: 18) {
                SectionHeader(
                    title: CCLocalized("metric.disk.title"),
                    subtitle: CCLocalized("metric.disk.subtitle"),
                    icon: "internaldrive.fill",
                    value: status.map { "\(Int(($0.usedFraction * 100).rounded()))%" } ?? "—",
                    accent: Color(red: 1.0, green: 0.64, blue: 0.30)
                )

                HorizontalProgressBar(
                    value: status?.usedFraction ?? 0,
                    color: Color(red: 1.0, green: 0.64, blue: 0.30)
                )

                if let status {
                    HStack(spacing: 8) {
                        ValueLabel(title: CCLocalized("disk.used"), value: status.usedText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ValueLabel(title: CCLocalized("disk.free"), value: status.freeText, alignment: .center)
                            .frame(maxWidth: .infinity, alignment: .center)
                        ValueLabel(title: CCLocalized("disk.total"), value: status.totalText, alignment: .trailing)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                } else {
                    UnavailableRow(message: CCLocalized("error.disk.read"))
                }

                CleanerActionControl(cleaner: cleaner, action: .disk)
            }
        }
    }
}

struct UptimeStatsBlock: View {
    let uptime: String

    var body: some View {
        GlassBlock {
            VStack(alignment: .leading, spacing: 18) {
                SectionHeader(
                    title: CCLocalized("metric.uptime.title"),
                    subtitle: CCLocalized("metric.uptime.subtitle"),
                    icon: "clock.fill",
                    value: "",
                    accent: Color(red: 0.29, green: 0.95, blue: 0.67)
                )

                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.055))
                        SoftAccentIcon(
                            name: "waveform.path.ecg",
                            size: 20,
                            weight: .semibold,
                            accent: Color(red: 0.29, green: 0.95, blue: 0.67)
                        )
                    }
                    .frame(width: 48, height: 48)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.07), lineWidth: 1)
                    )

                    VStack(alignment: .leading, spacing: 3) {
                        Text(CCLocalized("metric.uptime.active"))
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.60))
                        Text(uptime.isEmpty ? "—" : uptime)
                            .font(.system(size: 23, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.55)
                    }
                }
            }
        }
    }
}

struct HardwareSpecsBlock: View {
    let info: DeviceHardwareInfo?

    var body: some View {
        GlassBlock {
            VStack(alignment: .leading, spacing: 20) {
                SectionHeader(
                    title: CCLocalized("hardware.section.title"),
                    subtitle: CCLocalized("hardware.section.subtitle"),
                    icon: "iphone",
                    value: "",
                    accent: Color(red: 0.38, green: 0.72, blue: 1.0)
                )

                if let info {
                    HardwareSpecGroup(
                        title: CCLocalized("hardware.group.device"),
                        items: [
                            HardwareSpecItem(label: CCLocalized("hardware.device.family"), value: info.deviceFamily),
                            HardwareSpecItem(label: CCLocalized("hardware.device.identifier"), value: info.modelIdentifier),
                            HardwareSpecItem(label: CCLocalized("hardware.device.board"), value: info.boardIdentifier),
                            HardwareSpecItem(label: CCLocalized("hardware.device.os"), value: info.operatingSystem)
                        ]
                    )

                    HardwareSpecGroup(
                        title: CCLocalized("hardware.group.processor"),
                        items: [
                            HardwareSpecItem(label: CCLocalized("hardware.processor.architecture"), value: info.architecture),
                            HardwareSpecItem(label: CCLocalized("hardware.processor.logical_cores"), value: "\(info.logicalCoreCount)"),
                            HardwareSpecItem(label: CCLocalized("hardware.processor.active_cores"), value: "\(info.activeCoreCount)"),
                            HardwareSpecItem(label: CCLocalized("hardware.memory.physical"), value: info.physicalMemory),
                            HardwareSpecItem(label: CCLocalized("hardware.memory.page_size"), value: info.memoryPageSize),
                            HardwareSpecItem(label: CCLocalized("hardware.storage.capacity"), value: info.storageCapacity),
                            HardwareSpecItem(label: CCLocalized("hardware.storage.available"), value: info.storageAvailable)
                        ]
                    )

                    HardwareSpecGroup(
                        title: CCLocalized("hardware.group.display"),
                        items: [
                            HardwareSpecItem(label: CCLocalized("hardware.display.native_resolution"), value: info.nativeResolution),
                            HardwareSpecItem(label: CCLocalized("hardware.display.logical_resolution"), value: info.logicalResolution),
                            HardwareSpecItem(label: CCLocalized("hardware.display.scale"), value: info.displayScale),
                            HardwareSpecItem(label: CCLocalized("hardware.display.maximum_refresh"), value: info.maximumRefreshRate)
                        ]
                    )

                    HardwareSpecGroup(
                        title: CCLocalized("hardware.group.power"),
                        items: [
                            HardwareSpecItem(label: CCLocalized("hardware.battery.level"), value: info.batteryLevel),
                            HardwareSpecItem(label: CCLocalized("hardware.battery.state"), value: info.batteryState),
                            HardwareSpecItem(label: CCLocalized("hardware.battery.health"), value: info.batteryHealth),
                            HardwareSpecItem(label: CCLocalized("hardware.battery.wear"), value: info.batteryWear),
                            HardwareSpecItem(label: CCLocalized("hardware.battery.maximum_capacity"), value: info.batteryMaximumCapacity),
                            HardwareSpecItem(label: CCLocalized("hardware.battery.design_capacity"), value: info.batteryDesignCapacity),
                            HardwareSpecItem(label: CCLocalized("hardware.battery.cycle_count"), value: info.batteryCycleCount),
                            HardwareSpecItem(label: CCLocalized("hardware.thermal.state"), value: info.thermalState),
                            HardwareSpecItem(label: CCLocalized("hardware.low_power_mode"), value: info.lowPowerMode)
                        ]
                    )
                } else {
                    LoadingRow(message: CCLocalized("hardware.loading"))
                }
            }
        }
    }
}

private struct HardwareSpecItem: Identifiable {
    let label: String
    let value: String

    var id: String { label }
}

private struct HardwareSpecGroup: View {
    let title: String
    let items: [HardwareSpecItem]

    private let columns = [
        GridItem(.adaptive(minimum: 132), spacing: 10, alignment: .top)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.58))

            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.label)
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.52))
                            .lineLimit(1)

                        Text(item.value)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.90))
                            .lineLimit(2)
                            .minimumScaleFactor(0.70)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
                    .background(Color.white.opacity(0.055))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.07), lineWidth: 1)
                    )
                }
            }
        }
    }
}

struct GlassBlock<Content: View>: View {
    private let content: Content
    private let contentPadding: CGFloat
    private let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)

    init(padding: CGFloat = 20, @ViewBuilder content: () -> Content) {
        self.contentPadding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(contentPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.25))
            .clipShape(shape)
            .overlay(
                shape.stroke(Color.white.opacity(0.16), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.10), radius: 6, x: 0, y: 2)
    }
}

private struct SectionHeader: View {
    let title: String
    let subtitle: String
    let icon: String
    let value: String
    let accent: Color

    var body: some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Color.white.opacity(0.055))
                SoftAccentIcon(
                    name: icon,
                    size: 18,
                    weight: .semibold,
                    accent: accent
                )
            }
            .frame(width: 44, height: 44)
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(Color.white.opacity(0.07), lineWidth: 1)
            )
            .fixedSize()

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.60))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !value.isEmpty {
                Text(value)
                    .font(.system(size: 25, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                    .layoutPriority(1)
            }
        }
    }
}

private struct MetricProgressRow: View {
    let title: String
    let value: Double
    let valueText: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.64))
                .frame(width: 48, alignment: .leading)
                .lineLimit(1)

            HorizontalProgressBar(value: value, color: color, height: 8)

            Text(valueText)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.90))
                .frame(width: 34, alignment: .trailing)
                .lineLimit(1)
        }
    }
}

private struct HorizontalProgressBar: View {
    let value: Double
    let color: Color
    var height: CGFloat = 11

    private var normalizedValue: CGFloat {
        CGFloat(min(max(value, 0), 1))
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.16))

                Capsule()
                    .fill(color)
                    .overlay(
                        Capsule()
                            .fill(Color.white.opacity(0.68))
                    )
                    .frame(width: proxy.size.width * normalizedValue)
                    .shadow(color: color.opacity(0.18), radius: 4)
            }
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.35), value: value)
        .accessibilityValue(
            CCFormatted("accessibility.percent_format", Int((normalizedValue * 100).rounded()))
        )
    }
}

struct SoftAccentIcon: View {
    let name: String
    let size: CGFloat
    let weight: Font.Weight
    let accent: Color

    var body: some View {
        ZStack {
            Image(systemName: name)
                .font(.system(size: size, weight: weight))
                .foregroundColor(accent)
            Image(systemName: name)
                .font(.system(size: size, weight: weight))
                .foregroundColor(.white.opacity(0.68))
        }
    }
}

private struct ValueLabel: View {
    let title: String
    let value: String
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: 3) {
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.56))
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.90))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }
}

private struct DetailTile: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.54))
                Text(value)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.86))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            Spacer(minLength: 0)
        }
        .padding(11)
        .background(Color.white.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
    }
}

private struct LoadingRow: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
            Text(message)
                .font(.caption)
                .foregroundColor(.white.opacity(0.72))
        }
    }
}

private struct UnavailableRow: View {
    let message: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(message)
                .font(.caption)
        }
        .foregroundColor(Color(red: 1.0, green: 0.66, blue: 0.36))
    }
}
