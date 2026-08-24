//
//  ContentView.swift
//  CpuCores
//
//  Created by Lampadina_17 on 03/10/22.
//

import SwiftUI

struct ContentView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @StateObject private var cpuMonitor = CPUCoreMonitor()
    @StateObject private var memoryMonitor = SystemMemoryMonitor()
    @StateObject private var systemCleaner = SystemCleanerService()
    @State private var diskStatus: DiskStatus?
    @State private var uptime = ""

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
        }
        .padding(.horizontal, 2)
        .padding(.bottom, 2)
    }

    private func refreshSystemInfo() {
        memoryMonitor.refresh()
        diskStatus = DiskStatus.current()
        uptime = systemInfoProvider.displayUptime()
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
