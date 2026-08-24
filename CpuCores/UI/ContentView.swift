//
//  ContentView.swift
//  CpuCores
//
//  Created by Lampadina_17 on 03/10/22.
//

import SwiftUI

private enum DashboardSheet: String, Identifiable {
    case hardwareInfo
    case settings

    var id: String { rawValue }
}

struct ContentView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @StateObject private var cpuMonitor = CPUCoreMonitor()
    @StateObject private var memoryMonitor = SystemMemoryMonitor()
    @StateObject private var systemCleaner = SystemCleanerService()
    @State private var diskStatus: DiskStatus?
    @State private var uptime = ""
    @State private var presentedSheet: DashboardSheet?

    private let systemInfoProvider = SystemInfoProvider()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            SystemBackground()

            GeometryReader { proxy in
                let horizontalPadding: CGFloat = proxy.size.width < 390 ? 12 : 18
                let contentWidth = max(proxy.size.width - (horizontalPadding * 2), 0)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        header(isNarrow: contentWidth < 350)
                        dashboard(for: contentWidth)
                        CleanerDisclaimer()
                    }
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, proxy.size.width < 390 ? 14 : 20)
                    .padding(.bottom, 36)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            cpuMonitor.start()
            refreshSystemInfo()
        }
        .onDisappear {
            cpuMonitor.stop()
            systemCleaner.cancel()
        }
        .onReceive(timer) { _ in
            refreshSystemInfo()
        }
        .sheet(item: $presentedSheet) { sheet in
            Group {
                switch sheet {
                case .hardwareInfo:
                    HardwareInfoView()
                case .settings:
                    RefreshSettingsView()
                }
            }
        }
    }

    @ViewBuilder
    private func dashboard(for width: CGFloat) -> some View {
        if horizontalSizeClass == .regular && width >= 850 {
            wideDesktopDashboard()
        } else if horizontalSizeClass == .regular && width >= 610 {
            portraitTabletDashboard()
        } else {
            compactDashboard(width: width)
        }
    }

    private func compactDashboard(width: CGFloat) -> some View {
        Group {
            cpuBlock(grouped: horizontalSizeClass == .regular && width >= 520)
            memoryBlock
            diskBlock
            UptimeStatsBlock(uptime: uptime)
        }
    }

    private func wideDesktopDashboard() -> some View {
        Group {
            HStack(alignment: .top, spacing: 18) {
                VStack(spacing: 18) {
                    cpuBlock(grouped: true)
                    diskBlock
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 18) {
                    memoryBlock
                    UptimeStatsBlock(uptime: uptime)
                }
                .frame(maxWidth: .infinity)
            }

        }
    }

    private func portraitTabletDashboard() -> some View {
        Group {
            cpuBlock(grouped: true)

            HStack(alignment: .top, spacing: 18) {
                memoryBlock
                    .frame(maxWidth: .infinity)

                VStack(spacing: 18) {
                    diskBlock
                    UptimeStatsBlock(uptime: uptime)
                }
                .frame(maxWidth: .infinity)
            }

        }
    }

    private func cpuBlock(grouped: Bool) -> some View {
        CPUStatsBlock(
            cores: cpuMonitor.cores,
            overallLoad: cpuMonitor.overallLoad,
            errorMessage: cpuMonitor.errorMessage,
            usesGroupedLayout: grouped
        )
    }

    private var memoryBlock: some View {
        MemoryStatsBlock(
            reading: memoryMonitor.reading,
            errorMessage: memoryMonitor.errorMessage,
            cleaner: systemCleaner
        )
    }

    private var diskBlock: some View {
        DiskStatsBlock(
            status: diskStatus,
            cleaner: systemCleaner
        )
    }

    private func header(isNarrow: Bool) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(CCLocalized("app.title"))
                    .font(.system(size: isNarrow ? 25 : 30, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(CCLocalized("dashboard.subtitle"))
                    .font(isNarrow ? .caption : .subheadline)
                    .foregroundColor(.white.opacity(0.72))
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 8) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(Color(red: 0.28, green: 1.0, blue: 0.69))
                        .frame(width: 7, height: 7)
                        .shadow(color: Color.green.opacity(0.8), radius: 5)
                    Text(CCLocalized("status.live"))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.86))
                }
                .padding(.horizontal, isNarrow ? 9 : 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.09))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )

                Button {
                    presentedSheet = .hardwareInfo
                } label: {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white.opacity(0.88))
                        .frame(width: 34, height: 34)
                        .background(Color.white.opacity(0.09))
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.14), lineWidth: 1)
                        )
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel(CCLocalized("hardware.section.title"))

                Button {
                    presentedSheet = .settings
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.88))
                        .frame(width: 34, height: 34)
                        .background(Color.white.opacity(0.09))
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.14), lineWidth: 1)
                        )
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel(CCLocalized("accessibility.open_settings"))
            }
        }
        .padding(.horizontal, 2)
        .padding(.bottom, 2)
    }

    private func refreshSystemInfo() {
        memoryMonitor.refresh()
        let currentDiskStatus = DiskStatus.current()
        diskStatus = currentDiskStatus
        uptime = systemInfoProvider.displayUptime()
    }
}

private struct HardwareInfoView: View {
    @Environment(\.presentationMode) private var presentationMode
    @State private var hardwareInfo: DeviceHardwareInfo?

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationView {
            ZStack {
                SystemBackground()

                ScrollView(showsIndicators: false) {
                    HardwareSpecsBlock(info: hardwareInfo)
                        .padding(18)
                }
            }
            .navigationBarTitle(CCLocalized("hardware.section.title"), displayMode: .inline)
            .navigationBarItems(
                trailing: Button(CCLocalized("action.done")) {
                    presentationMode.wrappedValue.dismiss()
                }
            )
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .preferredColorScheme(.dark)
        .onAppear {
            refreshHardwareInfo()
        }
        .onReceive(timer) { _ in
            refreshHardwareInfo()
        }
    }

    private func refreshHardwareInfo() {
        hardwareInfo = DeviceHardwareInfo.current()
    }
}

private struct RefreshSettingsView: View {
    @Environment(\.presentationMode) private var presentationMode
    @AppStorage(WidgetRefreshSettings.storageKey) private var refreshIntervalMilliseconds =
        WidgetRefreshSettings.defaultMilliseconds

    private var intervalBinding: Binding<Double> {
        Binding(
            get: {
                Double(WidgetRefreshSettings.clamped(refreshIntervalMilliseconds))
            },
            set: { newValue in
                let milliseconds = WidgetRefreshSettings.clamped(Int(newValue.rounded()))
                refreshIntervalMilliseconds = milliseconds
                WidgetKeepAliveController.shared.updateRefreshInterval(milliseconds: milliseconds)
            }
        )
    }

    var body: some View {
        NavigationView {
            ZStack {
                SystemBackground()

                ScrollView(showsIndicators: false) {
                    GlassBlock {
                        VStack(alignment: .leading, spacing: 20) {
                            HStack(spacing: 14) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 19, weight: .semibold))
                                    .foregroundColor(Color(red: 0.24, green: 0.84, blue: 1.0))
                                    .frame(width: 44, height: 44)
                                    .background(Color.white.opacity(0.07))
                                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(CCLocalized("settings.refresh.title"))
                                        .font(.system(size: 16, weight: .bold, design: .rounded))
                                        .foregroundColor(.white)
                                    Text(CCLocalized("settings.refresh.subtitle"))
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.62))
                                }

                                Spacer(minLength: 8)

                                Text(CCFormatted("settings.refresh.value_format", refreshIntervalMilliseconds))
                                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white)
                            }

                            Slider(
                                value: intervalBinding,
                                in: Double(WidgetRefreshSettings.minimumMilliseconds)...Double(WidgetRefreshSettings.maximumMilliseconds),
                                step: Double(WidgetRefreshSettings.stepMilliseconds)
                            )
                            .accentColor(Color(red: 0.24, green: 0.84, blue: 1.0))

                            HStack {
                                Text(CCFormatted("settings.refresh.value_format", WidgetRefreshSettings.minimumMilliseconds))
                                Spacer()
                                Text(CCFormatted("settings.refresh.value_format", WidgetRefreshSettings.maximumMilliseconds))
                            }
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.52))

                            Text(CCLocalized("settings.refresh.description"))
                                .font(.footnote)
                                .foregroundColor(.white.opacity(0.64))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(18)
                }
            }
            .navigationBarTitle(CCLocalized("settings.title"), displayMode: .inline)
            .navigationBarItems(
                trailing: Button(CCLocalized("action.done")) {
                    presentationMode.wrappedValue.dismiss()
                }
            )
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .preferredColorScheme(.dark)
        .onAppear {
            let normalizedInterval = WidgetRefreshSettings.clamped(refreshIntervalMilliseconds)
            if normalizedInterval != refreshIntervalMilliseconds {
                refreshIntervalMilliseconds = normalizedInterval
                WidgetKeepAliveController.shared.updateRefreshInterval(milliseconds: normalizedInterval)
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
