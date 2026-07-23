import AppKit

/// 一次 GitHub Release 查询的结果。
struct ReleaseInfo {
    let version: String    // 规范化版本号，如 "1.3.0"
    let tag: String        // 原始 tag，如 "v1.3.0"
    let dmgURL: URL?       // .dmg 直链
    let pageURL: URL?      // 发行说明页
}

/// 更新检查与引导下载。纯系统能力（URLSession + NSWorkspace），无第三方依赖。
enum Updater {
    static let repo = "ljzxzxl/mac-amd-gpu-info"

    static var currentVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0"
    }

    /// 拉取最新 Release（回调在主线程）。
    static func fetchLatest(_ completion: @escaping (Result<ReleaseInfo, Error>) -> Void) {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else {
            completion(.failure(error("更新地址无效"))); return
        }
        var req = URLRequest(url: url, timeoutInterval: 12)
        req.setValue("MacAMDGPUInfo", forHTTPHeaderField: "User-Agent")   // GitHub API 要求带 UA
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: req) { data, resp, err in
            func done(_ r: Result<ReleaseInfo, Error>) { DispatchQueue.main.async { completion(r) } }
            if let err = err { done(.failure(err)); return }
            guard let http = resp as? HTTPURLResponse else { done(.failure(error("无网络响应"))); return }
            guard http.statusCode == 200, let data = data else {
                done(.failure(error("HTTP \(http.statusCode)"))); return
            }
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = obj["tag_name"] as? String else {
                done(.failure(error("解析更新信息失败"))); return
            }
            let page = (obj["html_url"] as? String).flatMap { URL(string: $0) }
            var dmg: URL?
            if let assets = obj["assets"] as? [[String: Any]] {
                for a in assets where (a["name"] as? String)?.hasSuffix(".dmg") == true {
                    dmg = (a["browser_download_url"] as? String).flatMap { URL(string: $0) }
                    if dmg != nil { break }
                }
            }
            done(.success(ReleaseInfo(version: normalize(tag), tag: tag, dmgURL: dmg, pageURL: page)))
        }.resume()
    }

    /// 语义比较：latest 是否比 current 新。
    static func isNewer(_ latest: String, than current: String) -> Bool {
        let a = latest.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// 下载 dmg 后用 NSWorkspace 打开（自动挂载并弹出安装窗）。
    /// 存到 Application Support（非 TCC 保护目录），避免写 ~/Downloads 被隐私权限拦截。
    static func downloadAndOpen(_ dmgURL: URL, completion: @escaping (Error?) -> Void) {
        URLSession.shared.downloadTask(with: dmgURL) { tmp, resp, err in
            func done(_ e: Error?) { DispatchQueue.main.async { completion(e) } }
            if let err = err { done(err); return }
            if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
                done(error("下载失败（HTTP \(http.statusCode)）")); return
            }
            guard let tmp = tmp else { done(error("下载失败：无临时文件")); return }
            do {
                let dir = try updatesDirectory()
                let name = dmgURL.lastPathComponent.hasSuffix(".dmg") ? dmgURL.lastPathComponent : "MacAMDGPUInfo.dmg"
                let dest = dir.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: dest.path) {
                    try FileManager.default.removeItem(at: dest)
                }
                try FileManager.default.moveItem(at: tmp, to: dest)
                NSWorkspace.shared.open(dest)
                done(nil)
            } catch {
                done(error)
            }
        }.resume()
    }

    /// 更新包存放目录：`~/Library/Application Support/MacAMDGPUInfo/Updates`（非 TCC 保护）。
    private static func updatesDirectory() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory,
                                               in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = base.appendingPathComponent("MacAMDGPUInfo/Updates", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func normalize(_ tag: String) -> String {
        var s = tag
        if s.hasPrefix("v") || s.hasPrefix("V") { s.removeFirst() }
        return s
    }

    private static func error(_ msg: String) -> NSError {
        NSError(domain: "Updater", code: -1, userInfo: [NSLocalizedDescriptionKey: msg])
    }
}
