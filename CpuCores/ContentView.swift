//
//  ContentView.swift
//  CpuCores
//
//  Created by Lampadina_17 on 03/10/22.
//

import SwiftUI
import QuartzCore
import Foundation
import Darwin

struct CpuCore: Identifiable {
    var id = UUID()
    var name: String
    var score: Double
}

struct ContentView: View {
    
    @State var cpu: Double
    @State var ram: String
    @State var disk: String
    @State var uptime: String
    
    var cores = [
        CpuCore(name: "1", score: 0.0),
        CpuCore(name: "2", score: 0.0),
        CpuCore(name: "3", score: 0.0),
        CpuCore(name: "4", score: 0.0),
        CpuCore(name: "5", score: 0.0),
        CpuCore(name: "6", score: 0.0),
    ]
    
    var body: some View {
        let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
        
        ZStack {
            LinearGradient(gradient: Gradient(colors: [.blue, .purple]), startPoint: .topLeading, endPoint: .bottomTrailing)
            
            VStack {
                /*
                VStack() {
                    Gauge(title: "CPU Usage", value: String("\(cpu)%"))
                    HStack {
                        ForEach(cores) { core in
                            CapsuleBar(value: Int(cpu), maxValue: 100, width: 6, height: 80, valueName: core.name, capsuleColor: ColorRGB(red: 255, green: 255, blue: 255)).padding(1)
                        }
                    }
                }
                .padding()
                .background(Color.white.opacity(0.3))
                .cornerRadius(25)
                .shadow(color: Color.black.opacity(0.2), radius: 7, x: 0, y: 0)
                */
                Gauge(title: "CPU Usage", value: String("\(cpu)%"))
                Gauge(title: "Ram Usage", value: ram)
                Gauge(title: "Disk Usage", value: disk)
                Gauge(title: "Uptime", value: uptime)
            }.onReceive(timer, perform: { _ in
                cpu = round(cpuUsage() * 10) / 10
                ram = displayRam()
                disk = displayDisk()
                uptime = displayUptime()
            })
        }.ignoresSafeArea(.all).preferredColorScheme(.dark)
    }
    
    func byteToMega(bytes: UInt64) -> UInt64 {
        let megabytes = bytes / (1024 * 1024)
        return megabytes;
    }
    
    func displayRam() -> String {
        let processInfo = ProcessInfo()
        let used = byteToMega(bytes: UInt64(memoryUsage()))
        let total = byteToMega(bytes: processInfo.physicalMemory)
        return "Used: \(used)/\(total) MB"
    }
    
    func displayDisk() -> String {
        let usedSpace = DiskStatus.usedDiskSpace.replacingOccurrences(of: "GB", with: "").replacingOccurrences(of: " ", with: "")
        let totalSpace = DiskStatus.totalDiskSpace.replacingOccurrences(of: "GB", with: "").replacingOccurrences(of: " ", with: "")
        return "Used: \(usedSpace)/\(totalSpace) GB"
    }
    
    func displayUptime() -> String {
        if let bootTime = bootTime() {
            let calendar = Calendar.current
            let now = Date()
            let components = calendar.dateComponents([.day, .hour, .minute], from: bootTime, to: now)
            if let days = components.day, let hours = components.hour, let minutes = components.minute {
                return "\(days)d \(hours)h \(minutes)m"
            }
        }
        return ""
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(cpu: 0, ram: "", disk: "", uptime: "")
    }
}

// https://github.com/dani-gavrilov/GDPerformanceView-Swift/blob/master/GDPerformanceView-Swift/GDPerformanceMonitoring/Performance%D0%A1alculator.swift
private extension ContentView {
    
    func cpuUsage() -> Double {
        var totalUsageOfCPU: Double = 0.0
        var threadsList: thread_act_array_t?
        var threadsCount = mach_msg_type_number_t(0)
        let threadsResult = withUnsafeMutablePointer(to: &threadsList) {
            return $0.withMemoryRebound(to: thread_act_array_t?.self, capacity: 1) {
                task_threads(mach_task_self_, $0, &threadsCount)
            }
        }
        
        if threadsResult == KERN_SUCCESS, let threadsList = threadsList {
            for index in 0..<threadsCount {
                var threadInfo = thread_basic_info()
                var threadInfoCount = mach_msg_type_number_t(THREAD_INFO_MAX)
                let infoResult = withUnsafeMutablePointer(to: &threadInfo) {
                    $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                        thread_info(threadsList[Int(index)], thread_flavor_t(THREAD_BASIC_INFO), $0, &threadInfoCount)
                    }
                }
                
                guard infoResult == KERN_SUCCESS else {
                    break
                }
                
                let threadBasicInfo = threadInfo as thread_basic_info
                if threadBasicInfo.flags & TH_FLAGS_IDLE == 0 {
                    totalUsageOfCPU = (totalUsageOfCPU + (Double(threadBasicInfo.cpu_usage) / Double(TH_USAGE_SCALE) * 100.0))
                }
            }
        }
        
        vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: threadsList)), vm_size_t(Int(threadsCount) * MemoryLayout<thread_t>.stride))
        return totalUsageOfCPU
    }
    
    func memoryUsage() -> UInt32 {
        var size = mach_msg_type_number_t(MemoryLayout<vm_statistics_data_t>.stride / MemoryLayout<integer_t>.stride)
        var vmStats = vm_statistics_data_t()
        
        _ = withUnsafeMutablePointer(to: &vmStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics(mach_host_self(), HOST_VM_INFO, $0, &size)
            }
        }
        
        return (UInt32(vmStats.active_count) + UInt32(vmStats.inactive_count) + UInt32(vmStats.wire_count)) * numericCast(vm_page_size)
    }
    
    func bootTime() -> Date? {
        var tv = timeval()
        var tvSize = MemoryLayout<timeval>.size
        let err = sysctlbyname("kern.boottime", &tv, &tvSize, nil, 0);
        guard err == 0, tvSize == MemoryLayout<timeval>.size else {
            return nil
        }
        return Date(timeIntervalSince1970: Double(tv.tv_sec) + Double(tv.tv_usec) / 1_000_000.0)
    }
}
