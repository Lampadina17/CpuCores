//
//  widget.swift
//  widget
//
//  Created by Lampadina_17 on 30/12/23.
//

import WidgetKit
import SwiftUI
import UIKit

struct WidgetSnapshot {
    let cpuFraction: Double
    let coreLoads: [Double]
    let ramFraction: Double
    let diskFraction: Double
    let batteryFraction: Double?
    let ramDetail: String
    let diskDetail: String
    let uptime: String

    static let placeholder = WidgetSnapshot(
        cpuFraction: 0.38,
        coreLoads: [0.24, 0.42, 0.31, 0.58, 0.19, 0.47, 0.35, 0.27],
        ramFraction: 0.61,
        diskFraction: 0.46,
        batteryFraction: 0.82,
        ramDetail: "3,7 GB / 6 GB",
        diskDetail: "118 GB / 256 GB",
        uptime: CCFormatted("uptime.format", 2, 7, 24)
    )
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
        if context.isPreview {
            completion(SimpleEntry(date: Date(), snapshot: .placeholder))
        } else {
            completion(makeEntry(at: Date()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
        let now = Date()
        let refreshDate = Calendar.current.date(byAdding: .minute, value: 5, to: now)
            ?? now.addingTimeInterval(5 * 60)
        completion(Timeline(entries: [makeEntry(at: now)], policy: .after(refreshDate)))
    }

    private func makeEntry(at date: Date) -> SimpleEntry {
        let provider = SystemInfoProvider()
        let cpu = provider.systemCPU(maxCores: 8)
        let memory = provider.systemMemory()
        let disk = DiskStatus.current()
        let battery = currentBatteryFraction()
        let measuredUptime = provider.displayUptime()

        let snapshot = WidgetSnapshot(
            cpuFraction: cpu?.overallLoad ?? 0,
            coreLoads: cpu?.coreLoads ?? [],
            ramFraction: memory?.usedFraction ?? 0,
            diskFraction: disk?.usedFraction ?? 0,
            batteryFraction: battery,
            ramDetail: memory.map { "\($0.usedText) / \($0.totalText)" } ?? CCLocalized("common.unavailable"),
            diskDetail: disk.map { "\($0.usedText) / \($0.totalText)" } ?? CCLocalized("common.unavailable"),
            uptime: measuredUptime.isEmpty ? "—" : measuredUptime
        )
        return SimpleEntry(date: date, snapshot: snapshot)
    }

    private func currentBatteryFraction() -> Double? {
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        let level = device.batteryLevel
        guard level >= 0 else { return nil }
        return min(max(Double(level), 0), 1)
    }
}

struct widgetEntryView: View {
    let entry: Provider.Entry

    @Environment(\.widgetFamily) private var family

    @ViewBuilder
    var body: some View {
        if #available(iOS 16.0, *) {
            switch family {
            case .accessoryCircular:
                AccessoryCircularWidgetView(snapshot: entry.snapshot)
                    .accessoryWidgetContainerBackground()
            case .accessoryRectangular:
                AccessoryRectangularWidgetView(snapshot: entry.snapshot)
                    .accessoryWidgetContainerBackground()
            case .accessoryInline:
                AccessoryInlineWidgetView(snapshot: entry.snapshot)
                    .accessoryWidgetContainerBackground()
            default:
                HomeScreenWidgetView(snapshot: entry.snapshot, family: family)
            }
        } else {
            HomeScreenWidgetView(snapshot: entry.snapshot, family: family)
        }
    }
}

struct widget: Widget {
    let kind = "widget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            widgetEntryView(entry: entry)
        }
        .configurationDisplayName(CCLocalized("widget.configuration.name"))
        .description(CCLocalized("widget.configuration.description"))
        .supportedFamilies(supportedWidgetFamilies())
    }
}

private func supportedWidgetFamilies() -> [WidgetFamily] {
    var families: [WidgetFamily] = [.systemSmall, .systemMedium, .systemLarge]
    if #available(iOS 16.0, *) {
        families += [.accessoryCircular, .accessoryRectangular, .accessoryInline]
    }
    return families
}

private struct HomeScreenWidgetView: View {
    let snapshot: WidgetSnapshot
    let family: WidgetFamily

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                SmallWidgetView(snapshot: snapshot)
            case .systemMedium:
                MediumWidgetView(snapshot: snapshot)
            default:
                LargeWidgetView(snapshot: snapshot)
            }
        }
        .widgetBackdrop()
    }
}

@available(iOS 16.0, *)
private struct AccessoryCircularWidgetView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        Gauge(value: normalizedFraction(snapshot.cpuFraction), in: 0...1) {
            Image(systemName: "cpu")
        } currentValueLabel: {
            VStack(spacing: -1) {
                Text(percentage(snapshot.cpuFraction))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                Text(CCLocalized("metric.cpu.title"))
                    .font(.system(size: 7, weight: .semibold, design: .rounded))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .widgetAccentable()
        .accessibilityLabel(CCLocalized("metric.cpu.title"))
        .accessibilityValue(percentage(snapshot.cpuFraction))
    }
}

@available(iOS 16.0, *)
private struct AccessoryRectangularWidgetView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "cpu")
                    .widgetAccentable()
                Text(CCLocalized("metric.cpu.title"))
                Spacer(minLength: 4)
                Text(percentage(snapshot.cpuFraction))
                    .fontWeight(.bold)
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))

            Gauge(value: normalizedFraction(snapshot.cpuFraction), in: 0...1) {
                EmptyView()
            }
            .gaugeStyle(.accessoryLinearCapacity)
            .widgetAccentable()

            HStack(spacing: 10) {
                AccessoryMetricValue(
                    title: CCLocalized("metric.ram.title"),
                    value: snapshot.ramFraction
                )
                Spacer(minLength: 0)
                AccessoryMetricValue(
                    title: CCLocalized("metric.disk.short"),
                    value: snapshot.diskFraction
                )
            }
        }
        .accessibilityElement(children: .combine)
    }
}

@available(iOS 16.0, *)
private struct AccessoryMetricValue: View {
    let title: String
    let value: Double

    var body: some View {
        HStack(spacing: 3) {
            Text(title)
            Text(percentage(value))
                .fontWeight(.bold)
        }
        .font(.system(size: 10, weight: .medium, design: .rounded))
        .lineLimit(1)
    }
}

@available(iOS 16.0, *)
private struct AccessoryInlineWidgetView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        Label {
            Text("\(CCLocalized("metric.cpu.title")) \(percentage(snapshot.cpuFraction))")
        } icon: {
            Image(systemName: "cpu")
        }
        .accessibilityLabel(CCLocalized("metric.cpu.title"))
        .accessibilityValue(percentage(snapshot.cpuFraction))
    }
}

private struct SmallWidgetView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        GeometryReader { geometry in
            let spacing: CGFloat = 9
            let diameter = min(
                (geometry.size.width - spacing) / 2,
                (geometry.size.height - spacing) / 2
            )

            VStack(spacing: spacing) {
                HStack(spacing: spacing) {
                    CircularWidgetMetric(
                        title: CCLocalized("metric.cpu.title"),
                        icon: "cpu",
                        value: snapshot.cpuFraction,
                        color: WidgetPalette.cpu
                    )
                    .frame(width: diameter, height: diameter)

                    CircularWidgetMetric(
                        title: CCLocalized("metric.ram.title"),
                        icon: "memorychip",
                        value: snapshot.ramFraction,
                        color: WidgetPalette.ram
                    )
                    .frame(width: diameter, height: diameter)
                }

                HStack(spacing: spacing) {
                    CircularWidgetMetric(
                        title: CCLocalized("metric.disk.short"),
                        icon: "internaldrive.fill",
                        value: snapshot.diskFraction,
                        color: WidgetPalette.disk
                    )
                    .frame(width: diameter, height: diameter)

                    CircularWidgetMetric(
                        title: CCLocalized("widget.battery"),
                        icon: "battery.100",
                        value: snapshot.batteryFraction,
                        color: WidgetPalette.battery
                    )
                    .frame(width: diameter, height: diameter)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(widgetLayoutPadding(12))
    }
}

private struct MediumWidgetView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        GeometryReader { geometry in
            let spacing: CGFloat = 12
            let columnWidth = (geometry.size.width - (spacing * 2)) / 3
            let diameter = min(columnWidth, geometry.size.height - 22)

            HStack(spacing: spacing) {
                MediumCircularMetric(
                    title: CCLocalized("metric.cpu.title"),
                    icon: "cpu",
                    value: snapshot.cpuFraction,
                    color: WidgetPalette.cpu,
                    diameter: diameter
                )
                .frame(width: columnWidth)

                MediumCircularMetric(
                    title: CCLocalized("metric.ram.title"),
                    icon: "memorychip",
                    value: snapshot.ramFraction,
                    color: WidgetPalette.ram,
                    diameter: diameter
                )
                .frame(width: columnWidth)

                MediumCircularMetric(
                    title: CCLocalized("metric.disk.short"),
                    icon: "internaldrive.fill",
                    value: snapshot.diskFraction,
                    color: WidgetPalette.disk,
                    diameter: diameter
                )
                .frame(width: columnWidth)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(widgetLayoutPadding(14))
    }
}

private struct LargeWidgetView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        GeometryReader { geometry in
            let spacing: CGFloat = 10
            let uptimeHeight: CGFloat = 40
            let flexibleHeight = max(0, geometry.size.height - uptimeHeight - (spacing * 2))
            let cpuHeight = flexibleHeight * 0.60
            let detailHeight = flexibleHeight - cpuHeight

            VStack(spacing: spacing) {
                CPUWidgetBlock(snapshot: snapshot)
                    .frame(height: cpuHeight)

                HStack(spacing: spacing) {
                    DetailedMetricBlock(
                        title: CCLocalized("metric.ram.title"),
                        icon: "memorychip",
                        value: snapshot.ramFraction,
                        detail: snapshot.ramDetail,
                        color: WidgetPalette.ram
                    )
                    DetailedMetricBlock(
                        title: CCLocalized("metric.disk.short"),
                        icon: "internaldrive.fill",
                        value: snapshot.diskFraction,
                        detail: snapshot.diskDetail,
                        color: WidgetPalette.disk
                    )
                }
                .frame(height: detailHeight)

                HStack(spacing: 10) {
                    FadedWidgetIcon(
                        name: "clock.fill",
                        size: 12,
                        weight: .semibold,
                        accent: WidgetPalette.uptime
                    )
                    Text(CCLocalized("metric.uptime.title"))
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.46))
                    Spacer()
                    Text(snapshot.uptime)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .frame(height: uptimeHeight)
                .glassWidgetBlock(cornerRadius: 14)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .padding(widgetLayoutPadding(15))
    }
}

private struct CircularWidgetMetric: View {
    let title: String
    let icon: String
    let value: Double?
    let color: Color
    var iconSize: CGFloat = 16

    private var normalizedValue: Double {
        min(max(value ?? 0, 0), 1)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.11), lineWidth: 6)

            Circle()
                .trim(from: 0, to: normalizedValue)
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            if value == nil {
                Image(systemName: icon)
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundColor(.white.opacity(0.30))
            } else {
                FadedWidgetIcon(
                    name: icon,
                    size: iconSize,
                    weight: .semibold,
                    accent: color
                )
            }
        }
        .padding(3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value.map(percentage) ?? CCLocalized("common.unavailable"))
    }
}

private struct MediumCircularMetric: View {
    let title: String
    let icon: String
    let value: Double
    let color: Color
    let diameter: CGFloat

    var body: some View {
        VStack(spacing: 6) {
            CircularWidgetMetric(
                title: title,
                icon: icon,
                value: value,
                color: color,
                iconSize: min(max(diameter * 0.38, 30), 42)
            )
            .frame(width: diameter, height: diameter)

            HStack(spacing: 4) {
                Text(title)
                    .foregroundColor(.white.opacity(0.50))
                Text(percentage(value))
                    .foregroundColor(.white)
            }
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct MetricTile: View {
    let title: String
    let icon: String
    let value: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                FadedWidgetIcon(
                    name: icon,
                    size: 10,
                    weight: .semibold,
                    accent: color
                )
                Spacer(minLength: 0)
                Text(percentage(value))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }

            Text(title)
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.48))

            WidgetProgressBar(value: value, color: color, height: 5)
        }
        .padding(9)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .glassWidgetBlock(cornerRadius: 14)
    }
}

private struct UptimeTile: View {
    let uptime: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FadedWidgetIcon(
                name: "clock.fill",
                size: 10,
                weight: .semibold,
                accent: WidgetPalette.uptime
            )
            Text(CCLocalized("metric.uptime.title"))
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.48))
            Text(uptime)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(9)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .glassWidgetBlock(cornerRadius: 14)
    }
}

private struct CPUWidgetBlock: View {
    let snapshot: WidgetSnapshot

    private var displayedCores: [Double] {
        Array(snapshot.coreLoads.prefix(8))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                FadedWidgetIcon(
                    name: "cpu",
                    size: 12,
                    weight: .semibold,
                    accent: WidgetPalette.cpu
                )
                Text(CCLocalized("widget.cpu.multicore"))
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.62))
                Spacer()
                Text(percentage(snapshot.cpuFraction))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }

            WidgetProgressBar(value: snapshot.cpuFraction, color: WidgetPalette.cpu, height: 7)

            if displayedCores.isEmpty {
                Text(CCLocalized("widget.core.unavailable"))
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.42))
            } else {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())],
                    spacing: 5
                ) {
                    ForEach(Array(displayedCores.enumerated()), id: \.offset) { index, load in
                        CoreWidgetRow(index: index, load: load)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .glassWidgetBlock(cornerRadius: 16)
    }
}

private struct CoreWidgetRow: View {
    let index: Int
    let load: Double

    var body: some View {
        HStack(spacing: 5) {
            Text(CCFormatted("widget.core.short_format", index + 1))
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.48))
                .frame(width: 14, alignment: .leading)
            WidgetProgressBar(value: load, color: coreColor(load), height: 4)
            Text(percentage(load))
                .font(.system(size: 8, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.76))
                .frame(width: 26, alignment: .trailing)
        }
    }

    private func coreColor(_ value: Double) -> Color {
        if value >= 0.80 { return WidgetPalette.hot }
        if value >= 0.55 { return WidgetPalette.warm }
        return WidgetPalette.cool
    }
}

private struct DetailedMetricBlock: View {
    let title: String
    let icon: String
    let value: Double
    let detail: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                FadedWidgetIcon(
                    name: icon,
                    size: 11,
                    weight: .semibold,
                    accent: color
                )
                Text(title)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.56))
                Spacer()
                Text(percentage(value))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }

            WidgetProgressBar(value: value, color: color, height: 6)

            Text(detail)
                .font(.system(size: 8, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.52))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(11)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .glassWidgetBlock(cornerRadius: 15)
    }
}

private struct WidgetProgressBar: View {
    let value: Double
    let color: Color
    let height: CGFloat

    private var normalizedValue: CGFloat {
        CGFloat(min(max(value, 0), 1))
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.16))
                Capsule()
                    .fill(color)
                    .overlay(
                        Capsule()
                            .fill(Color.white.opacity(0.68))
                    )
                    .frame(width: geometry.size.width * normalizedValue)
                    .shadow(color: color.opacity(0.16), radius: 2)
            }
        }
        .frame(height: height)
    }
}

private struct FadedWidgetIcon: View {
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

private struct WidgetBackdrop: View {
    var body: some View {
        GeometryReader { geometry in
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
                    endRadius: max(geometry.size.width, geometry.size.height) * 0.62
                )

                RadialGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.08, green: 0.78, blue: 0.82).opacity(0.16),
                        Color.clear
                    ]),
                    center: UnitPoint(x: 0.10, y: 0.92),
                    startRadius: 0,
                    endRadius: max(geometry.size.width, geometry.size.height) * 0.58
                )

                RadialGradient(
                    gradient: Gradient(colors: [
                        Color(red: 1.0, green: 0.40, blue: 0.12).opacity(0.09),
                        Color.clear
                    ]),
                    center: UnitPoint(x: 0.92, y: 0.88),
                    startRadius: 0,
                    endRadius: max(geometry.size.width, geometry.size.height) * 0.38
                )
            }
        }
    }
}

private struct WidgetBackdropModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.containerBackground(for: .widget) {
                WidgetBackdrop()
            }
        } else {
            ZStack {
                WidgetBackdrop()
                content
            }
        }
    }
}

private struct AccessoryWidgetContainerBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.containerBackground(for: .widget) {
                WidgetBackdrop()
            }
        } else {
            content
        }
    }
}

private struct GlassWidgetBlockModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(Color.white.opacity(0.16))
            .clipShape(shape)
            .overlay(shape.stroke(Color.white.opacity(0.16), lineWidth: 0.75))
    }
}

private extension View {
    func widgetBackdrop() -> some View {
        modifier(WidgetBackdropModifier())
    }

    func accessoryWidgetContainerBackground() -> some View {
        modifier(AccessoryWidgetContainerBackgroundModifier())
    }

    func glassWidgetBlock(cornerRadius: CGFloat) -> some View {
        modifier(GlassWidgetBlockModifier(cornerRadius: cornerRadius))
    }
}

private enum WidgetPalette {
    static let cpu = Color(red: 0.24, green: 0.84, blue: 1.0)
    static let ram = Color(red: 0.78, green: 0.48, blue: 1.0)
    static let disk = Color(red: 1.0, green: 0.64, blue: 0.30)
    static let uptime = Color(red: 0.29, green: 0.95, blue: 0.67)
    static let battery = Color(red: 0.29, green: 0.95, blue: 0.67)
    static let cool = Color(red: 0.27, green: 0.96, blue: 0.82)
    static let warm = Color(red: 1.0, green: 0.72, blue: 0.27)
    static let hot = Color(red: 1.0, green: 0.33, blue: 0.42)
}

private func percentage(_ value: Double) -> String {
    "\(Int((normalizedFraction(value) * 100).rounded()))%"
}

private func normalizedFraction(_ value: Double) -> Double {
    min(max(value, 0), 1)
}

private func widgetLayoutPadding(_ legacyPadding: CGFloat) -> CGFloat {
    if #available(iOS 17.0, *) {
        return 0
    }
    return legacyPadding
}
