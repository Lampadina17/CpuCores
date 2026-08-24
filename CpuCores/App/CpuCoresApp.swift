//
//  CpuCoresApp.swift
//  CpuCores
//
//  Created by Lampadina_17 on 03/10/22.
//

import SwiftUI
import WidgetKit

@main
struct CpuCoresApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .onAppear {
                    WidgetKeepAliveController.shared.start()
                }
        }
        .onChange(of: scenePhase) { phase in
            guard phase == .background else { return }
            WidgetCenter.shared.reloadTimelines(ofKind: "widget")
        }
    }
}
