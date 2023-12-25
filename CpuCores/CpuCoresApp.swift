//
//  CpuCoresApp.swift
//  CpuCores
//
//  Created by Lampadina_17 on 03/10/22.
//

import SwiftUI


@main
struct CpuCoresApp: App {
    
    var body: some Scene {
        WindowGroup {
            ContentView(cpu: 0, ram: "", disk: "", uptime: "")
        }
    }
}
