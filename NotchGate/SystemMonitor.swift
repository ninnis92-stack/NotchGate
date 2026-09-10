import Foundation
import Darwin
import IOKit
import IOKit.ps
import CoreWLAN
import AppKit
import SwiftUI

@Observable
final class SystemMonitor {
    var cpuUsage: Double = 0
    var cpuUser: Double = 0
    var cpuSystem: Double = 0
    var cpuIdle: Double = 0
    var memoryUsage: Double = 0
    var memoryUsedBytes: Double = 0
    var memoryWiredBytes: Double = 0
    var memoryCompressedBytes: Double = 0
    var memorySwapUsedBytes: Double = 0
    var batteryPercent: Int?
    var isCharging = false
    var onACPower = false
    var batteryMinutes: Int?
    var diskUsage: Double = 0
    var diskUsedBytes: Double = 0
    var diskTotalBytes: Double = 0
    var diskName = "Macintosh HD"
    var now = Date()
    var wifiPowered = true
    var wifiConnected = false
    var cpuHistory: [Double] = []
    var memoryHistory: [Double] = []
    var batteryHistory: [Double] = []
    var diskHistory: [Double] = []
    var downloadBytesPerSecond: Double = 0
    var uploadBytesPerSecond: Double = 0
    var downloadHistory: [Double] = []
    var uploadHistory: [Double] = []

    let coreCount = ProcessInfo.processInfo.activeProcessorCount
    private(set) var memoryTotalBytes = Double(ProcessInfo.processInfo.physicalMemory)

    private var previousCPU = host_cpu_load_info_data_t()
    private var hasCPUBaseline = false
    private var timer: Timer?
    private var refreshInterval: TimeInterval = 1
    private var previousNetwork: (up: UInt64, down: UInt64, at: Date)?

    var thermalLabel: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "Nominal"
        case .fair: return "Fair"
        case .serious: return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }

    var uptime: TimeInterval { ProcessInfo.processInfo.systemUptime }

    func start(interval: TimeInterval = 1) {
        let clamped = [1, 5, 10].contains(interval) ? interval : 1
        if timer != nil, abs(clamped - refreshInterval) < 0.01 { return }
        refreshInterval = clamped
        timer?.invalidate()
        refresh()
        let timer = Timer(timeInterval: clamped, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.refresh()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func refresh() {
        cpuUsage = readCPUUsage()
        readMemory()
        readBattery()
        readDiskUsage()
        readWiFi()
        readNetwork()
        now = Date()
        let historyCap = max(30, Int(300 / max(refreshInterval, 1)))
        push(cpuUsage, onto: &cpuHistory, cap: historyCap)
        push(memoryUsage, onto: &memoryHistory, cap: historyCap)
        if batteryPercent != nil {
            push(Double(batteryPercent ?? 0), onto: &batteryHistory, cap: historyCap)
        }
        push(diskUsage, onto: &diskHistory, cap: historyCap)
        push(downloadBytesPerSecond, onto: &downloadHistory, cap: historyCap)
        push(uploadBytesPerSecond, onto: &uploadHistory, cap: historyCap)
    }

    private func push(_ value: Double, onto history: inout [Double], cap: Int) {
        history.append(value)
        if history.count > cap { history.removeFirst(history.count - cap) }
    }

    private func readCPUUsage() -> Double {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }

        defer {
            previousCPU = info
            hasCPUBaseline = true
        }

        guard result == KERN_SUCCESS, hasCPUBaseline else { return cpuUsage }

        let userDelta = max(0, Double(info.cpu_ticks.0) - Double(previousCPU.cpu_ticks.0))
        let systemDelta = max(0, Double(info.cpu_ticks.1) - Double(previousCPU.cpu_ticks.1))
        let idleDelta = max(0, Double(info.cpu_ticks.2) - Double(previousCPU.cpu_ticks.2))
        let niceDelta = max(0, Double(info.cpu_ticks.3) - Double(previousCPU.cpu_ticks.3))
        let total = userDelta + systemDelta + idleDelta + niceDelta
        guard total > 0 else { return cpuUsage }
        cpuUser = (userDelta / total) * 100
        cpuSystem = ((systemDelta + niceDelta) / total) * 100
        cpuIdle = (idleDelta / total) * 100
        return min(100, ((userDelta + systemDelta + niceDelta) / total) * 100)
    }

    private func readMemory() {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }

        let pageSize = Double(vm_kernel_page_size)
        // Matches Activity Monitor: App Memory + Wired + Compressed.
        let internalPages = Double(stats.internal_page_count)
        let purgeablePages = Double(stats.purgeable_count)
        let wiredPages = Double(stats.wire_count)
        let compressedPages = Double(stats.compressor_page_count)
        memoryWiredBytes = wiredPages * pageSize
        memoryCompressedBytes = compressedPages * pageSize
        memoryUsedBytes = max(0, (internalPages - purgeablePages + wiredPages + compressedPages) * pageSize)
        let total = Double(Self.physicalMemoryBytes())
        memoryTotalBytes = total
        guard total > 0 else { return }
        memoryUsage = min(100, (memoryUsedBytes / total) * 100)

        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0 {
            memorySwapUsedBytes = Double(swap.xsu_used)
        }
    }

    private static func physicalMemoryBytes() -> UInt64 {
        var value: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        if sysctlbyname("hw.memsize", &value, &size, nil, 0) == 0, value > 0 {
            return value
        }
        return ProcessInfo.processInfo.physicalMemory
    }

    private func readBattery() {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else {
            batteryPercent = nil
            isCharging = false
            onACPower = false
            batteryMinutes = nil
            return
        }

        let descriptions = list.compactMap { source in
            IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any]
        }
        let battery = descriptions.first { ($0[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType }
            ?? descriptions.first { ($0[kIOPSTypeKey] as? String)?.localizedCaseInsensitiveContains("battery") == true }

        guard let description = battery else {
            batteryPercent = nil
            isCharging = false
            onACPower = descriptions.contains { ($0[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue }
            batteryMinutes = nil
            return
        }

        let current = (description[kIOPSCurrentCapacityKey] as? Int)
            ?? (description[kIOPSCurrentCapacityKey] as? NSNumber)?.intValue
        let maxCapacity = (description[kIOPSMaxCapacityKey] as? Int)
            ?? (description[kIOPSMaxCapacityKey] as? NSNumber)?.intValue
        if let current, let maxCapacity, maxCapacity > 0 {
            batteryPercent = min(100, Int((Double(current) / Double(maxCapacity) * 100).rounded()))
        } else if let current {
            batteryPercent = min(100, current)
        } else {
            batteryPercent = nil
        }

        let state = description[kIOPSPowerSourceStateKey] as? String
        onACPower = state == kIOPSACPowerValue
        isCharging = description[kIOPSIsChargingKey] as? Bool ?? false
        if isCharging {
            batteryMinutes = description[kIOPSTimeToFullChargeKey] as? Int
        } else {
            batteryMinutes = description[kIOPSTimeToEmptyKey] as? Int
        }
        if let minutes = batteryMinutes, minutes < 0 { batteryMinutes = nil }
    }

    private func readDiskUsage() {
        let root = URL(fileURLWithPath: "/")
        let values = try? root.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeTotalCapacityKey,
            .volumeNameKey
        ])
        guard let available = values?.volumeAvailableCapacityForImportantUsage,
              let total = values?.volumeTotalCapacity,
              total > 0 else {
            return
        }
        diskTotalBytes = Double(total)
        diskUsedBytes = Double(total) - Double(available)
        diskUsage = min(100, (diskUsedBytes / Double(total)) * 100)
        diskName = values?.volumeName ?? "Macintosh HD"
    }

    private func readWiFi() {
        let iface = CWWiFiClient.shared().interface()
        wifiPowered = iface?.powerOn() ?? false
        if let iface, wifiPowered {
            wifiConnected = iface.ssid() != nil || iface.serviceActive()
        } else {
            wifiConnected = false
        }
    }

    private func readNetwork() {
        let snapshot = Self.interfaceBytes()
        let now = Date()
        if let previous = previousNetwork {
            let elapsed = max(now.timeIntervalSince(previous.at), 0.2)
            downloadBytesPerSecond = Double(byteDelta(snapshot.down, previous.down)) / elapsed
            uploadBytesPerSecond = Double(byteDelta(snapshot.up, previous.up)) / elapsed
        }
        previousNetwork = (snapshot.up, snapshot.down, now)
    }

    private static func interfaceBytes() -> (up: UInt64, down: UInt64) {
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0, let first = addrs else { return (0, 0) }
        defer { freeifaddrs(addrs) }
        var up: UInt64 = 0
        var down: UInt64 = 0
        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            let name = String(cString: current.pointee.ifa_name)
            let flags = Int32(current.pointee.ifa_flags)
            let skip = name.hasPrefix("lo") || name.hasPrefix("utun") || name.hasPrefix("awdl")
                || name.hasPrefix("llw") || name.hasPrefix("gif") || name.hasPrefix("stf")
                || name.hasPrefix("anpi") || name.hasPrefix("bridge") || name.hasPrefix("ap")
            if !skip, (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0,
               let addr = current.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK),
               let data = current.pointee.ifa_data {
                let stats = data.assumingMemoryBound(to: if_data.self).pointee
                down += UInt64(stats.ifi_ibytes)
                up += UInt64(stats.ifi_obytes)
            }
            pointer = current.pointee.ifa_next
        }
        return (up, down)
    }

    private func byteDelta(_ current: UInt64, _ previous: UInt64) -> UInt64 {
        if current >= previous { return current - previous }
        let max32 = UInt64(UInt32.max)
        if previous <= max32, current <= max32 {
            return (max32 - previous) + current + 1
        }
        return current
    }

    func formattedRate(_ bytesPerSecond: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(max(0, bytesPerSecond)), countStyle: .file) + "/s"
    }

    func trend(_ history: [Double]) -> Int {
        guard history.count >= 4 else { return 0 }
        let recent = history.suffix(3).reduce(0, +) / 3
        let previous = history.dropLast(3).suffix(3)
        guard !previous.isEmpty else { return 0 }
        let older = previous.reduce(0, +) / Double(previous.count)
        let delta = recent - older
        if abs(delta) < 1 { return 0 }
        return delta > 0 ? 1 : -1
    }

    func average(_ history: [Double]) -> Double {
        guard !history.isEmpty else { return 0 }
        return history.reduce(0, +) / Double(history.count)
    }

    func averageLastMinute(_ history: [Double]) -> Double {
        let samples = max(1, Int((60 / max(refreshInterval, 1)).rounded()))
        let slice = Array(history.suffix(samples))
        guard !slice.isEmpty else { return 0 }
        return slice.reduce(0, +) / Double(slice.count)
    }

    func peakLastMinute(_ history: [Double]) -> Double {
        let samples = max(1, Int((60 / max(refreshInterval, 1)).rounded()))
        return history.suffix(samples).max() ?? 0
    }

    func peak(_ history: [Double]) -> Double {
        history.max() ?? 0
    }

    func loadRating(for usage: Double) -> String {
        switch usage {
        case ..<20: return "Light"
        case ..<45: return "Moderate"
        case ..<75: return "High"
        default: return "Heavy"
        }
    }

    func formattedBytes(_ bytes: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(max(0, bytes)), countStyle: .memory)
    }

    var formattedUptime: String {
        let total = Int(uptime)
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    var powerSourceLabel: String {
        if batteryPercent == nil { return "No battery" }
        if isCharging { return "Charging" }
        if onACPower { return "Power adapter" }
        return "On battery"
    }

    var batteryTimeLabel: String {
        guard let minutes = batteryMinutes, minutes > 0 else {
            if batteryPercent == nil { return "No battery reported" }
            if isCharging { return "Calculating time to full" }
            if onACPower { return "Plugged in" }
            return "Calculating time remaining"
        }
        let hours = minutes / 60
        let mins = minutes % 60
        let time = hours > 0 ? "\(hours)h \(mins)m" : "\(mins)m"
        return isCharging ? "\(time) to full" : "\(time) remaining"
    }

    var batteryShortTime: String {
        guard let minutes = batteryMinutes, minutes > 0 else { return "" }
        let hours = minutes / 60
        let mins = minutes % 60
        return hours > 0 ? "\(hours)h \(mins)m" : "\(mins)m"
    }

    var hardwareModel: String {
        sysctlString("hw.model")
    }

    var cpuBrand: String {
        let brand = sysctlString("machdep.cpu.brand_string")
        return brand.isEmpty ? "\(coreCount)-core CPU" : brand
    }

    private func sysctlString(_ name: String) -> String {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return "" }
        return String(cString: buffer)
    }
}

enum StatHealth {
    static func load(_ value: Double) -> Color {
        switch value {
        case ..<45: return Color(red: 0.45, green: 0.92, blue: 0.62)
        case ..<75: return Color(red: 1.0, green: 0.78, blue: 0.28)
        default: return Color(red: 1, green: 0.42, blue: 0.38)
        }
    }

    static func battery(_ percent: Int, charging: Bool) -> Color {
        if charging { return Color(red: 0.45, green: 0.92, blue: 0.62) }
        if percent <= 20 { return Color(red: 1, green: 0.42, blue: 0.38) }
        if percent <= 40 { return Color(red: 1.0, green: 0.78, blue: 0.28) }
        return Color(red: 0.45, green: 0.92, blue: 0.62)
    }
}
