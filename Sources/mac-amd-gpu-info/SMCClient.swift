import Foundation
import IOKit

/// 真·SMC 读取器（AppleSMC）：固定 80 字节缓冲 + 明确字段偏移，避免 Swift 结构体与 C 对齐不一致。
/// 只读、无需 root（与 iStatistica/iStats 同一数据源）。核显场景用它取 CPU 温度/风扇/功耗。
/// 注：与 SMCReader（那个基于 IOHIDEvent 读 Apple Silicon SoC 温度的）是两码事，勿混淆。
enum SMCClient {
    private static let size = 80
    private static var conn: io_connect_t = 0
    private static var opened = false

    private static func ensureOpen() -> Bool {
        if opened { return conn != 0 }
        opened = true
        let svc = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching("AppleSMC"))
        guard svc != 0 else { return false }
        defer { IOObjectRelease(svc) }
        return IOServiceOpen(svc, mach_task_self_, 0, &conn) == KERN_SUCCESS
    }

    // MARK: - 低层读取

    private static func fcc(_ s: String) -> UInt32 { var r: UInt32 = 0; for c in s.utf8 { r = (r << 8) | UInt32(c) }; return r }
    private static func wU32(_ b: inout [UInt8], _ o: Int, _ v: UInt32) {
        b[o] = UInt8(v & 0xff); b[o+1] = UInt8((v >> 8) & 0xff); b[o+2] = UInt8((v >> 16) & 0xff); b[o+3] = UInt8((v >> 24) & 0xff)
    }
    private static func rU32(_ b: [UInt8], _ o: Int) -> UInt32 {
        UInt32(b[o]) | UInt32(b[o+1]) << 8 | UInt32(b[o+2]) << 16 | UInt32(b[o+3]) << 24
    }
    private static func typeString(_ v: UInt32) -> String {
        let b = [UInt8((v >> 24) & 0xff), UInt8((v >> 16) & 0xff), UInt8((v >> 8) & 0xff), UInt8(v & 0xff)]
        return (String(bytes: b, encoding: .ascii) ?? "").trimmingCharacters(in: .whitespaces)
    }
    private static func call(_ input: [UInt8]) -> [UInt8]? {
        var inp = input; var out = [UInt8](repeating: 0, count: size); var osz = size
        return IOConnectCallStructMethod(conn, 2, &inp, size, &out, &osz) == KERN_SUCCESS ? out : nil
    }

    /// 读取键的 (类型, 数据字节)。偏移：key@0, data8@42(9=取信息/5=读数据), dataSize@28, dataType@32, result@40, bytes@48。
    static func read(_ key: String) -> (type: String, bytes: [UInt8])? {
        guard ensureOpen() else { return nil }
        var b = [UInt8](repeating: 0, count: size); wU32(&b, 0, fcc(key)); b[42] = 9
        guard let o1 = call(b), o1[40] == 0 else { return nil }
        let sz = Int(rU32(o1, 28)); let type = typeString(rU32(o1, 32))
        guard sz > 0, sz <= 32 else { return nil }
        var b2 = [UInt8](repeating: 0, count: size); wU32(&b2, 0, fcc(key)); wU32(&b2, 28, UInt32(sz)); b2[42] = 5
        guard let o2 = call(b2), o2[40] == 0 else { return nil }
        return (type, Array(o2[48 ..< 48 + sz]))
    }

    private static func decode(_ type: String, _ b: [UInt8]) -> Double? {
        switch type {
        case "sp78": guard b.count >= 2 else { return nil }; return Double(Int16(bitPattern: UInt16(b[0]) << 8 | UInt16(b[1]))) / 256.0
        case "fpe2": guard b.count >= 2 else { return nil }; return Double(UInt16(b[0]) << 8 | UInt16(b[1])) / 4.0
        case "sp96": guard b.count >= 2 else { return nil }; return Double(Int16(bitPattern: UInt16(b[0]) << 8 | UInt16(b[1]))) / 64.0
        case "flt":  guard b.count >= 4 else { return nil }; return Double(Float(bitPattern: UInt32(b[0]) | UInt32(b[1]) << 8 | UInt32(b[2]) << 16 | UInt32(b[3]) << 24))
        case "ui8", "ui16", "ui32": var v: UInt64 = 0; for x in b { v = (v << 8) | UInt64(x) }; return Double(v)
        default: return nil
        }
    }

    private static func value(_ key: String) -> Double? {
        guard let (t, b) = read(key) else { return nil }
        return decode(t, b)
    }

    // MARK: - 语义读取（CPU 温度/风扇/功耗）

    static func cpuTemperature() -> Int? {
        for k in ["TC0P", "TC0D", "TC0E", "TC0F", "TCXC"] {
            if let v = value(k), v > 0, v < 130 { return Int(v.rounded()) }
        }
        return nil
    }
    static func cpuFanRPM() -> Int? {
        if let v = value("F0Ac"), v >= 0 { return Int(v.rounded()) }
        return nil
    }
    static func cpuPowerW() -> Double? {
        for k in ["PCPT", "PCPC", "PSTR"] {
            if let v = value(k), v > 0, v < 400 { return v }
        }
        return nil
    }
}
