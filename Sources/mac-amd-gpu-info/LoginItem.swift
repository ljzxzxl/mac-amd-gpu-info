import Foundation
import ServiceManagement

/// 登录自启动封装（macOS 13+ 的 SMAppService.mainApp）。
enum LoginItem {
    static var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    /// 设置登录项；成功返回 true，失败返回 false（调用方回滚 UI）。
    @discardableResult
    static func set(_ on: Bool) -> Bool {
        guard #available(macOS 13.0, *) else { return false }
        do {
            if on {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else {
                if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            }
            return true
        } catch {
            NSLog("LoginItem set(\(on)) 失败: \(error.localizedDescription)")
            return false
        }
    }
}
