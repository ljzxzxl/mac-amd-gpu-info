import Foundation

struct VBIOSInfo {
    var partNumber: String?
    var atomVersion: String?
    var date: String?
    var board: String?
    var subsystem: String?
    var memoryVendor: String?
    var brand: String?
    var memoryType: String?
}

/// 从 VBIOS 二进制里抽取可读铭牌信息（等价于对固件做一次 strings + 正则）。
enum VBIOSDecoder {

    static func decode(_ data: Data) -> VBIOSInfo {
        let text = asciiRuns(data)
        var info = VBIOSInfo()
        // 料号末段可能是字母开头（如 113-34830M4-U02），故末段放宽为字母数字变长；保留 1\d{2}- 前缀避免误匹配日期。
        info.partNumber = firstMatch(#"1\d{2}-[0-9A-Za-z]+-[0-9A-Za-z]{2,}"#, in: text)
        info.atomVersion = firstMatch(#"ATOMBIOSBK-AMD VER[0-9.]+"#, in: text)?
            .replacingOccurrences(of: "ATOMBIOSBK-AMD VER", with: "")
        info.date = firstMatch(#"\d{2}/\d{2}/\d{2} \d{2}:\d{2}"#, in: text)

        let lines = text.components(separatedBy: "\n")
        // 板卡标识大小写不敏感（真实串为全大写 POLARIS21），展示时保留原始大小写。
        info.board = lines.first {
            let u = $0.uppercased()
            return u.contains("POLARIS") || u.contains("NAVI") || u.contains("VEGA")
        }?.trimmingCharacters(in: .whitespaces)
        info.subsystem = lines.first { $0.contains("config.h") }?
            .components(separatedBy: "\\").first?
            .trimmingCharacters(in: .whitespaces)

        let vendors = ["ELPIDA", "HYNIX", "SK HYNIX", "SAMSUNG", "MICRON"]
        info.memoryVendor = vendors.first { text.uppercased().contains($0) }?.capitalized

        let brands = ["SAPPHIRE", "POWERCOLOR", "ASUS", "MSI", "GIGABYTE", "XFX", "HIS", "VISIONTEK", "DATALAND", "YESTON"]
        info.brand = brands.first { text.uppercased().contains($0) }?.capitalized

        // 显存类型推断：机型库未命中时的兜底来源（本卡子系统含 GD5 → GDDR5）。
        let up = text.uppercased()
        if up.contains("GDDR6") { info.memoryType = "GDDR6" }
        else if up.contains("GDDR5") || up.contains("GD5") { info.memoryType = "GDDR5" }
        else if up.contains("HBM2") { info.memoryType = "HBM2" }
        else if up.contains("HBM") { info.memoryType = "HBM" }
        return info
    }

    // MARK: - helpers

    /// 提取长度 >= minLen 的可打印 ASCII 片段，用换行拼接（模仿 `strings`）。
    private static func asciiRuns(_ data: Data, minLen: Int = 4) -> String {
        var out = ""
        var run = ""
        for b in data {
            if b >= 0x20 && b <= 0x7E {
                run.append(Character(UnicodeScalar(b)))
            } else {
                if run.count >= minLen { out += run + "\n" }
                run = ""
            }
        }
        if run.count >= minLen { out += run }
        return out
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let m = re.firstMatch(in: text, range: range),
              let r = Range(m.range, in: text) else { return nil }
        return String(text[r])
    }
}
