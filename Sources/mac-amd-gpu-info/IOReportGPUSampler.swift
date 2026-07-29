import Foundation
import IOKit

/// Apple Silicon 免 root 采集 GPU 实时功耗与活跃频率。
///
/// powermetrics 自身即基于 IOReport 实现，而 IOReport 的 GPU 能耗与性能状态通道对普通用户可读，
/// 因此直接对接 IOReport 可同时去掉提权、子进程与临时文件三层依赖。
/// - 功耗：`Energy Model` 组的 GPU 能耗通道，取两次采样的能量差 / 时间差。
/// - 频率：`GPU Stats / GPU Performance States` 的 P-State 驻留计数，按 pmgr 的 DVFS 频率表加权平均。
final class IOReportGPUSampler {
    static let shared = IOReportGPUSampler()

    struct Sample {
        var powerW: Double?
        var coreMHz: Int?
    }

    // MARK: - 私有 API 绑定

    private typealias CopyChannelsFn = @convention(c) (CFString?, CFString?, UInt64, UInt64, UInt64) -> Unmanaged<CFMutableDictionary>?
    private typealias CreateSubFn = @convention(c) (UnsafeMutableRawPointer?, CFMutableDictionary, UnsafeMutablePointer<Unmanaged<CFMutableDictionary>?>?, UInt64, CFTypeRef?) -> Unmanaged<AnyObject>?
    private typealias CreateSamplesFn = @convention(c) (AnyObject, CFMutableDictionary, CFTypeRef?) -> Unmanaged<CFDictionary>?
    private typealias CreateDeltaFn = @convention(c) (CFDictionary, CFDictionary, CFTypeRef?) -> Unmanaged<CFDictionary>?
    private typealias IntValueFn = @convention(c) (CFDictionary, Int32) -> Int64
    private typealias GetStringFn = @convention(c) (CFDictionary) -> Unmanaged<CFString>?
    private typealias GetStringIdxFn = @convention(c) (CFDictionary, Int32) -> Unmanaged<CFString>?
    private typealias GetCountFn = @convention(c) (CFDictionary) -> Int32

    private struct API {
        let copyChannels: CopyChannelsFn
        let createSubscription: CreateSubFn
        let createSamples: CreateSamplesFn
        let createDelta: CreateDeltaFn
        let simpleValue: IntValueFn
        let unitLabel: GetStringFn
        let channelName: GetStringFn
        let stateCount: GetCountFn
        let stateName: GetStringIdxFn
        let stateResidency: IntValueFn
    }

    private let api: API?
    private let lock = NSLock()

    /// 两次真实采样的最小间隔：状态栏 2s、传感器页 1s 会并发调用，低于该间隔直接复用上次结果。
    private let minInterval: CFTimeInterval = 0.4

    private var energyChannels: CFMutableDictionary?
    private var energySubscription: AnyObject?
    private var prevEnergy: CFDictionary?

    private var perfChannels: CFMutableDictionary?
    private var perfSubscription: AnyObject?
    private var prevPerf: CFDictionary?

    private var prevTime: CFTimeInterval = 0
    private var cached = Sample()
    private var cachedTime: CFTimeInterval = 0

    /// GPU DVFS 频率表（索引 0 为 OFF 档，单位 MHz），来自 pmgr 的 voltage-states9。
    private lazy var freqTable: [Int] = Self.readGPUFreqTable()

    private init() {
        guard let lib = dlopen("/usr/lib/libIOReport.dylib", RTLD_LAZY),
              let pCopy = dlsym(lib, "IOReportCopyChannelsInGroup"),
              let pSub = dlsym(lib, "IOReportCreateSubscription"),
              let pSamples = dlsym(lib, "IOReportCreateSamples"),
              let pDelta = dlsym(lib, "IOReportCreateSamplesDelta"),
              let pSimple = dlsym(lib, "IOReportSimpleGetIntegerValue"),
              let pUnit = dlsym(lib, "IOReportChannelGetUnitLabel"),
              let pName = dlsym(lib, "IOReportChannelGetChannelName"),
              let pStCount = dlsym(lib, "IOReportStateGetCount"),
              let pStName = dlsym(lib, "IOReportStateGetNameForIndex"),
              let pStRes = dlsym(lib, "IOReportStateGetResidency")
        else {
            api = nil
            return
        }
        api = API(copyChannels: unsafeBitCast(pCopy, to: CopyChannelsFn.self),
                  createSubscription: unsafeBitCast(pSub, to: CreateSubFn.self),
                  createSamples: unsafeBitCast(pSamples, to: CreateSamplesFn.self),
                  createDelta: unsafeBitCast(pDelta, to: CreateDeltaFn.self),
                  simpleValue: unsafeBitCast(pSimple, to: IntValueFn.self),
                  unitLabel: unsafeBitCast(pUnit, to: GetStringFn.self),
                  channelName: unsafeBitCast(pName, to: GetStringFn.self),
                  stateCount: unsafeBitCast(pStCount, to: GetCountFn.self),
                  stateName: unsafeBitCast(pStName, to: GetStringIdxFn.self),
                  stateResidency: unsafeBitCast(pStRes, to: IntValueFn.self))
    }

    // MARK: - 对外接口

    var isAvailable: Bool { api != nil }

    /// 读取一次采样。首次调用只建立基线，返回空值；之后每次返回上一间隔的平均功耗与活跃频率。
    func read() -> Sample {
        guard let api = api else { return Sample() }
        lock.lock()
        defer { lock.unlock() }

        let now = CFAbsoluteTimeGetCurrent()
        if cachedTime > 0, now - cachedTime < minInterval { return cached }

        prepareSubscriptions(api)

        var sample = Sample()
        let dt = now - prevTime

        if let chans = energyChannels, let sub = energySubscription,
           let cur = api.createSamples(sub, chans, nil)?.takeRetainedValue() {
            if let prev = prevEnergy, dt > 0.05,
               let delta = api.createDelta(prev, cur, nil)?.takeRetainedValue() {
                sample.powerW = parsePower(api, delta, dt: dt)
            }
            prevEnergy = cur
        }

        if let chans = perfChannels, let sub = perfSubscription,
           let cur = api.createSamples(sub, chans, nil)?.takeRetainedValue() {
            if let prev = prevPerf, dt > 0.05,
               let delta = api.createDelta(prev, cur, nil)?.takeRetainedValue() {
                sample.coreMHz = parseFrequency(api, delta)
            }
            prevPerf = cur
        }

        prevTime = now
        // 首帧只建基线：保留上次有效值，避免 UI 闪空。
        if sample.powerW == nil && sample.coreMHz == nil && cachedTime > 0 { return cached }
        cached = sample
        cachedTime = now
        return sample
    }

    // MARK: - 订阅

    private func prepareSubscriptions(_ api: API) {
        if energySubscription == nil,
           let chans = filteredChannels(api, group: "Energy Model", subgroup: nil,
                                        match: { $0 == "GPU Energy" || $0 == "GPU" }) {
            var subbed: Unmanaged<CFMutableDictionary>?
            if let sub = api.createSubscription(nil, chans, &subbed, 0, nil)?.takeRetainedValue() {
                energySubscription = sub
                energyChannels = chans
            }
        }
        if perfSubscription == nil,
           let chans = filteredChannels(api, group: "GPU Stats", subgroup: "GPU Performance States",
                                        match: { $0.hasPrefix("GPUPH") }) {
            var subbed: Unmanaged<CFMutableDictionary>?
            if let sub = api.createSubscription(nil, chans, &subbed, 0, nil)?.takeRetainedValue() {
                perfSubscription = sub
                perfChannels = chans
            }
        }
    }

    /// 只订阅需要的通道（Energy Model 一组有上百个通道，全量采样是无谓开销）。
    private func filteredChannels(_ api: API, group: String, subgroup: String?,
                                  match: (String) -> Bool) -> CFMutableDictionary? {
        guard let all = api.copyChannels(group as CFString, subgroup as CFString?, 0, 0, 0)?.takeRetainedValue(),
              let items = channelArray(all) else { return nil }

        var arrayCB = kCFTypeArrayCallBacks
        guard let picked = CFArrayCreateMutable(kCFAllocatorDefault, 0, &arrayCB) else { return nil }
        for ch in items where match(api.channelName(ch)?.takeUnretainedValue() as String? ?? "") {
            CFArrayAppendValue(picked, Unmanaged.passUnretained(ch).toOpaque())
        }
        guard CFArrayGetCount(picked) > 0 else { return nil }

        var keyCB = kCFTypeDictionaryKeyCallBacks
        var valueCB = kCFTypeDictionaryValueCallBacks
        guard let out = CFDictionaryCreateMutable(kCFAllocatorDefault, 1, &keyCB, &valueCB) else { return nil }
        CFDictionarySetValue(out,
                             Unmanaged.passUnretained(Self.channelsKey).toOpaque(),
                             Unmanaged.passUnretained(picked).toOpaque())
        return out
    }

    private static let channelsKey = "IOReportChannels" as CFString

    /// 以原生 CF 类型遍历 IOReportChannels——IOReport 的取值函数会写回字典，
    /// 桥接成 Swift Dictionary 会因不可变副本触发 unrecognized selector 崩溃。
    private func channelArray(_ dict: CFDictionary) -> [CFDictionary]? {
        guard let raw = CFDictionaryGetValue(dict, Unmanaged.passUnretained(Self.channelsKey).toOpaque()) else { return nil }
        let arr = unsafeBitCast(raw, to: CFArray.self)
        let n = CFArrayGetCount(arr)
        guard n > 0 else { return nil }
        return (0..<n).map { unsafeBitCast(CFArrayGetValueAtIndex(arr, $0), to: CFDictionary.self) }
    }

    // MARK: - 解析

    private func parsePower(_ api: API, _ delta: CFDictionary, dt: CFTimeInterval) -> Double? {
        guard let items = channelArray(delta) else { return nil }
        var best: Double?
        for ch in items {
            guard let name = api.channelName(ch)?.takeUnretainedValue() as String? else { continue }
            let raw = api.simpleValue(ch, 0)
            guard raw > 0 else { continue }
            let unit = api.unitLabel(ch)?.takeUnretainedValue() as String? ?? ""
            let joules: Double
            switch unit.trimmingCharacters(in: .whitespaces) {
            case "nJ": joules = Double(raw) / 1e9
            case "uJ", "µJ": joules = Double(raw) / 1e6
            case "mJ": joules = Double(raw) / 1e3
            case "J": joules = Double(raw)
            default: continue
            }
            // AGX 的 "GPU Energy" 精度高于 PMGR 的 "GPU"，优先采用。
            if name == "GPU Energy" { return joules / dt }
            best = joules / dt
        }
        return best
    }

    private func parseFrequency(_ api: API, _ delta: CFDictionary) -> Int? {
        guard !freqTable.isEmpty, let items = channelArray(delta) else { return nil }
        var weighted = 0.0
        var total = 0.0
        for ch in items {
            let n = api.stateCount(ch)
            guard n > 0 else { continue }
            for i in 0..<n {
                guard let state = api.stateName(ch, i)?.takeUnretainedValue() as String? else { continue }
                let residency = Double(api.stateResidency(ch, i))
                guard residency > 0, state.hasPrefix("P"), let idx = Int(state.dropFirst()) else { continue }
                let mhz = idx < freqTable.count ? freqTable[idx] : freqTable[freqTable.count - 1]
                weighted += Double(mhz) * residency
                total += residency
            }
        }
        // 全程处于 OFF 档时没有活跃驻留，与 powermetrics 的 active frequency 一致地报 0。
        guard total > 0 else { return 0 }
        return Int((weighted / total).rounded())
    }

    /// 从 pmgr 读取 GPU 的 DVFS 频率表（voltage-states9：每 8 字节一组，前 4 字节为频率）。
    private static func readGPUFreqTable() -> [Int] {
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOPortDefault, IOServiceMatching("AppleARMIODevice"), &it) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(it) }

        var result: [Int] = []
        var service = IOIteratorNext(it)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(it)
            }
            var name = [CChar](repeating: 0, count: 128)
            guard IORegistryEntryGetName(service, &name) == KERN_SUCCESS,
                  String(cString: name) == "pmgr" else { continue }
            guard let data = IORegistryEntryCreateCFProperty(service, "voltage-states9" as CFString,
                                                             kCFAllocatorDefault, 0)?.takeRetainedValue() as? Data,
                  data.count >= 8 else { continue }
            result = data.withUnsafeBytes { raw -> [Int] in
                (0..<(raw.count / 8)).map { i in
                    let v = raw.loadUnaligned(fromByteOffset: i * 8, as: UInt32.self)
                    // 部分机型该表以 Hz 记录，统一折算到 MHz。
                    return Int(v > 1_000_000 ? v / 1_000_000 : v)
                }
            }
            if !result.isEmpty { break }
        }
        return result
    }
}
