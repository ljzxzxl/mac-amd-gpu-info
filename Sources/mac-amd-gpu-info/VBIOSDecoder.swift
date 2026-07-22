import Foundation

struct VBIOSInfo {
    var partNumber: String?
    var atomVersion: String?
    var date: String?
    var board: String?
    var subsystem: String?
    var memoryVendor: String?
    var brand: String?
}

/// 从 VBIOS 二进制里抽取可读铭牌信息（等价于对固件做一次 strings + 正则）。
enum VBIOSDecoder {

    static func decode(_ data: Data) -> VBIOSInfo {
        let text = asciiRuns(data)
        var info = VBIOSInfo()
        info.partNumber = firstMatch(#"1\d{2}-[0-9A-Za-z]+-\d{3}"#, in: text)
        info.atomVersion = firstMatch(#"ATOMBIOSBK-AMD VER[0-9.]+"#, in: text)?
            .replacingOccurrences(of: "ATOMBIOSBK-AMD VER", with: "")
        info.date = firstMatch(#"\d{2}/\d{2}/\d{2} \d{2}:\d{2}"#, in: text)

        let lines = text.components(separatedBy: "\n")
        info.board = lines.first { $0.contains("Polaris") || $0.contains("Navi") || $0.contains("Vega") }?
            .trimmingCharacters(in: .whitespaces)
        info.subsystem = lines.first { $0.contains("config.h") }?
            .components(separatedBy: "\\").first?
            .trimmingCharacters(in: .whitespaces)

        let vendors = ["ELPIDA", "HYNIX", "SK HYNIX", "SAMSUNG", "MICRON"]
        info.memoryVendor = vendors.first { text.uppercased().contains($0) }?.capitalized

        let brands = ["SAPPHIRE", "POWERCOLOR", "ASUS", "MSI", "GIGABYTE", "XFX", "HIS", "VISIONTEK", "DATALAND", "YESTON"]
        info.brand = brands.first { text.uppercased().contains($0) }?.capitalized
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
