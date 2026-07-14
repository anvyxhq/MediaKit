//
//  PerfMetrics.swift
//  ScannerKit
//
//  Created by AnhPT on 14/07/2026.
//

import Darwin

/// Lightweight on-device performance metrics for profiling the live scanner —
/// the app-process CPU load and the memory footprint iOS actually uses for
/// jetsam decisions. Read them on a timer while tuning; there's no cost when
/// you don't call them.
public enum PerfMetrics {

    /// Physical memory footprint in bytes (`phys_footprint`) — the value iOS uses
    /// to decide out-of-memory kills, not `resident_size`.
    public static func memoryFootprintBytes() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }

    /// Footprint in megabytes.
    public static func memoryFootprintMB() -> Double {
        Double(memoryFootprintBytes()) / (1024 * 1024)
    }

    /// Total CPU usage of this process across all non-idle threads, in percent
    /// (can exceed 100 on multiple cores).
    public static func cpuUsagePercent() -> Double {
        var threads: thread_act_array_t?
        var count = mach_msg_type_number_t(0)
        guard task_threads(mach_task_self_, &threads, &count) == KERN_SUCCESS, let threads else { return 0 }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: threads)),
                          vm_size_t(Int(count) * MemoryLayout<thread_t>.stride))
        }
        let basicInfoCount = mach_msg_type_number_t(
            MemoryLayout<thread_basic_info_data_t>.size / MemoryLayout<natural_t>.size)
        var total = 0.0
        for index in 0..<Int(count) {
            var info = thread_basic_info()
            var infoCount = basicInfoCount
            let result = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(infoCount)) {
                    thread_info(threads[index], thread_flavor_t(THREAD_BASIC_INFO), $0, &infoCount)
                }
            }
            if result == KERN_SUCCESS, info.flags & TH_FLAGS_IDLE == 0 {
                total += Double(info.cpu_usage) / Double(TH_USAGE_SCALE) * 100.0
            }
            mach_port_deallocate(mach_task_self_, threads[index])
        }
        return total
    }

    /// A one-shot snapshot of CPU + memory.
    public static func snapshot() -> (cpuPercent: Double, memoryMB: Double) {
        (cpuUsagePercent(), memoryFootprintMB())
    }
}
