import Foundation
import UIKit
import EventKit
import Contacts
import HealthKit
import AVFoundation

// MARK: - Shortcuts Action Handler
//
// 核心设计变化 (vs OpenClaw 原方案):
//   OpenClaw: LLM 输出 tool_call → Handler 直接调用系统 API (EventKit/CNContactStore)
//   PhoneClaw(iOS版): LLM 输出 tool_call → Handler 生成 iOS Shortcuts JSON → 用户导入 Shortcuts 执行
//
// 优势:
//   1. 无需系统级权限 (Contacts/Calendar 写权限)
//   2. 动作可审计、可编辑、可撤销
//   3. 符合 iOS 平台规范, 不违反 App Store 审核
//   4. 支持自动化触发 (Location/Time/App Open)
//
// 工具分为两类:
//   A. 读取类 (read): 仍然本地执行 (无需写入权限), 如 calendar-query, contacts-search
//   B. 写入类 (write): 输出 Shortcuts JSON, 由用户导入执行, 如 calendar-create, contacts-upsert

enum ShortcutsTools {
    
    // MARK: - Contract
    
    private static let shortcutsContract = PhoneGroundToolContract(
        evidenceTypes: [.system],
        answerContract: .none,
        freshness: .staticKnowledge
    )
    
    // MARK: - Register
    
    static func register(into registry: ToolRegistry) {
        
        // ── shortcuts-generate (通用快捷指令生成器) ──
        registry.register(RegisteredTool(
            name: "shortcuts-generate",
            description: tr(
                "根据用户意图生成 iOS 快捷指令 JSON, 用户可一键导入快捷指令 App 执行。无需系统权限, 替代直接写入日历/通讯录/短信等操作。",
                "Generate an iOS Shortcuts automation JSON based on user intent. Users can import it into the Shortcuts app for execution. No system permissions needed.",
                "ユーザーの意図に基づいて iOS ショートカット JSON を生成します。ショートカット App にインポートして実行できます。システム権限不要。"
            ),
            parameters: tr(
                "action_type: 动作类型 (say/send_sms/call/email/calendar_event/reminder/set_volume/set_brightness/set_wifi/set_bluetooth/set_flashlight/open_url/open_app/show_alert/create_note/wait/vibrate/play_sound/set_clipboard), params: 动作参数 JSON (按 action_type 不同而定)",
                "action_type: action type (say/send_sms/call/email/calendar_event/reminder/set_volume/set_brightness/set_wifi/set_bluetooth/set_flashlight/open_url/open_app/show_alert/create_note/wait/vibrate/play_sound/set_clipboard), params: action parameters JSON (varies by action_type)",
                "action_type: アクションタイプ（say/send_sms/call/email/calendar_event/reminder/set_volume/set_brightness/set_wifi/set_bluetooth/set_flashlight/open_url/open_app/show_alert/create_note/wait/vibrate/play_sound/set_clipboard）, params: パラメータ JSON"
            ),
            phoneGroundContract: shortcutsContract,
            requiredParameters: ["action_type"],
            execute: { args in
                try await generateCanonical(args).detail
            },
            executeCanonical: { args in
                try await generateCanonical(args)
            }
        ))
        
        // ── shortcuts-export (导出完整快捷指令文件) ──
        registry.register(RegisteredTool(
            name: "shortcuts-export",
            description: tr(
                "将生成的快捷指令 JSON 导出为 .shortcut 文件, 供用户通过快捷指令 App 导入",
                "Export generated Shortcuts JSON as a .shortcut file for importing into the Shortcuts app",
                "生成されたショートカット JSON を .shortcut ファイルとしてエクスポートします"
            ),
            parameters: tr(
                "json: 快捷指令 JSON 字符串, filename: 文件名（可选, 默认使用名称）",
                "json: Shortcuts JSON string, filename: file name (optional, defaults to name)",
                "json: ショートカット JSON 文字列, filename: ファイル名（任意, 名称がデフォルト）"
            ),
            phoneGroundContract: shortcutsContract,
            requiredParameters: ["json"],
            skipFollowUp: true,
            execute: { args in
                try await exportCanonical(args).detail
            },
            executeCanonical: { args in
                try await exportCanonical(args)
            }
        ))
        
        // ── shortcuts-copy-to-clipboard (复制 JSON 到剪贴板) ──
        registry.register(RegisteredTool(
            name: "shortcuts-copy",
            description: tr(
                "将快捷指令 JSON 复制到系统剪贴板, 方便用户粘贴到快捷指令 App",
                "Copy Shortcuts JSON to system clipboard for pasting into the Shortcuts app",
                "ショートカット JSON をシステムクリップボードにコピーします"
            ),
            parameters: tr(
                "json: 快捷指令 JSON 字符串",
                "json: Shortcuts JSON string",
                "json: ショートカット JSON 文字列"
            ),
            phoneGroundContract: shortcutsContract,
            requiredParameters: ["json"],
            skipFollowUp: true,
            execute: { args in
                try await copyCanonical(args).detail
            },
            executeCanonical: { args in
                try await copyCanonical(args)
            }
        ))
    }
    
    // MARK: - Generate (核心: 根据意图生成 Shortcuts JSON)
    
    private static func generateCanonical(_ args: [String: Any]) async throws -> CanonicalToolResult {
        guard let actionType = stringArg(args["action_type"]),
              !actionType.isEmpty else {
            return shortcutsFailure(
                summary: tr("请指定动作类型。", "Please specify an action type.", "アクションタイプを指定してください。"),
                detail: tr("缺少 action_type 参数", "Missing 'action_type' parameter", "action_type パラメータがありません"),
                errorCode: "ACTION_TYPE_MISSING"
            )
        }
        
        let params = args["params"] as? [String: Any] ?? [:]
        let workflow: ShortcutWorkflow
        
        switch actionType.lowercased() {
        case "say":
            let text = stringArg(params["text"]) ?? stringArg(params["message"]) ?? ""
            workflow = ShortcutWorkflowBuilder(name: "朗读")
                .say(text, language: stringArg(params["language"]) ?? "zh-Hans")
                .build()
        
        case "send_sms", "sms":
            let to = arrayArg(params["to"]) ?? [stringArg(params["to"]) ?? ""]
            let body = stringArg(params["body"]) ?? ""
            workflow = ShortcutWorkflowBuilder(name: "发送短信")
                .sendSMS(to: to, body: body)
                .build()
        
        case "call":
            let number = stringArg(params["number"]) ?? ""
            workflow = ShortcutWorkflowBuilder(name: "拨打电话")
                .callPhone(number)
                .build()
        
        case "email":
            let to = arrayArg(params["to"]) ?? [stringArg(params["to"]) ?? ""]
            let subject = stringArg(params["subject"]) ?? ""
            let body = stringArg(params["body"]) ?? ""
            workflow = ShortcutWorkflowBuilder(name: "发送邮件")
                .sendEmail(to: to, subject: subject, body: body)
                .build()
        
        case "calendar_event", "calendar":
            let title = stringArg(params["title"]) ?? "新日程"
            let start = stringArg(params["start"]) ?? ""
            let end = stringArg(params["end"]) ?? ""
            let location = stringArg(params["location"])
            let notes = stringArg(params["notes"])
            workflow = ShortcutWorkflowBuilder(name: "创建日历事件")
                .addCalendarEvent(
                    title: title,
                    startDate: start,
                    endDate: end,
                    location: location,
                    notes: notes,
                    calendar: stringArg(params["calendar"]) ?? "iCloud"
                )
                .build()
        
        case "reminder":
            let title = stringArg(params["title"]) ?? "新提醒"
            let dueDate = stringArg(params["due_date"]) ?? stringArg(params["duedate"])
            let notes = stringArg(params["notes"])
            workflow = ShortcutWorkflowBuilder(name: "创建提醒")
                .addReminder(title: title, dueDate: dueDate, notes: notes)
                .build()
        
        case "set_volume":
            let level = doubleArg(params["level"]) ?? 0.5
            workflow = ShortcutWorkflowBuilder(name: "设置音量")
                .setVolume(level)
                .build()
        
        case "set_brightness":
            let level = doubleArg(params["level"]) ?? 0.5
            workflow = ShortcutWorkflowBuilder(name: "设置亮度")
                .setBrightness(level)
                .build()
        
        case "set_wifi":
            let enabled = boolArg(params["enabled"]) ?? true
            workflow = ShortcutWorkflowBuilder(name: enabled ? "开启 Wi-Fi" : "关闭 Wi-Fi")
                .setWiFi(enabled: enabled)
                .build()
        
        case "set_bluetooth":
            let enabled = boolArg(params["enabled"]) ?? true
            workflow = ShortcutWorkflowBuilder(name: enabled ? "开启蓝牙" : "关闭蓝牙")
                .setBluetooth(enabled: enabled)
                .build()
        
        case "set_flashlight", "flashlight", "torch":
            let enabled = boolArg(params["enabled"]) ?? true
            workflow = ShortcutWorkflowBuilder(name: enabled ? "开启手电筒" : "关闭手电筒")
                .setFlashlight(enabled: enabled)
                .build()
        
        case "set_airplane_mode", "airplane_mode":
            let enabled = boolArg(params["enabled"]) ?? true
            workflow = ShortcutWorkflowBuilder(name: enabled ? "开启飞行模式" : "关闭飞行模式")
                .setAirplaneMode(enabled: enabled)
                .build()
        
        case "open_url", "url":
            let url = stringArg(params["url"]) ?? ""
            workflow = ShortcutWorkflowBuilder(name: "打开链接")
                .openURL(url)
                .build()
        
        case "open_app", "app":
            let bundleId = stringArg(params["bundle_id"]) ?? stringArg(params["bundle"]) ?? ""
            workflow = ShortcutWorkflowBuilder(name: "打开应用")
                .openApp(bundleId)
                .build()
        
        case "show_alert", "alert":
            let message = stringArg(params["message"]) ?? ""
            let title = stringArg(params["title"])
            workflow = ShortcutWorkflowBuilder(name: "显示通知")
                .showAlert(message, title: title)
                .build()
        
        case "create_note", "note":
            let title = stringArg(params["title"]) ?? "新备忘录"
            let body = stringArg(params["body"]) ?? ""
            workflow = ShortcutWorkflowBuilder(name: "创建备忘录")
                .createNote(title, body: body)
                .build()
        
        case "set_clipboard", "clipboard":
            let text = stringArg(params["text"]) ?? ""
            workflow = ShortcutWorkflowBuilder(name: "设置剪贴板")
                .setClipboard(text)
                .build()
        
        case "wait":
            let seconds = doubleArg(params["seconds"]) ?? 1.0
            workflow = ShortcutWorkflowBuilder(name: "等待")
                .wait(seconds: seconds)
                .build()
        
        case "vibrate":
            workflow = ShortcutWorkflowBuilder(name: "震动")
                .vibrate()
                .build()
        
        case "play_sound", "sound":
            let name = stringArg(params["name"]) ?? "Bottle"
            workflow = ShortcutWorkflowBuilder(name: "播放声音")
                .playSound(name)
                .build()
        
        default:
            return shortcutsFailure(
                summary: tr("不支持的动作类型: \(actionType)", "Unsupported action type: \(actionType)", "サポートされていないアクションタイプ: \(actionType)"),
                detail: tr(
                    "可用类型: say, send_sms, call, email, calendar_event, reminder, set_volume, set_brightness, set_wifi, set_bluetooth, set_flashlight, open_url, open_app, show_alert, create_note, set_clipboard, wait, vibrate, play_sound",
                    "Available types: say, send_sms, call, email, calendar_event, reminder, set_volume, set_brightness, set_wifi, set_bluetooth, set_flashlight, open_url, open_app, show_alert, create_note, set_clipboard, wait, vibrate, play_sound",
                    "利用可能なタイプ: say, send_sms, call, email, calendar_event, reminder, set_volume, set_brightness, set_wifi, set_bluetooth, set_flashlight, open_url, open_app, show_alert, create_note, set_clipboard, wait, vibrate, play_sound"
                ),
                errorCode: "UNSUPPORTED_ACTION_TYPE"
            )
        }
        
        let jsonString = workflow.toJSONString(prettyPrinted: true)
        
        let summary = tr(
            "已生成快捷指令: \(workflow.name)\n\nJSON:\n\(jsonString)\n\n使用方法: 复制到快捷指令 App → 粘贴 JSON → 运行",
            "Generated Shortcut: \(workflow.name)\n\nJSON:\n\(jsonString)\n\nHow to use: Copy to Shortcuts app → Paste JSON → Run",
            "ショートカットを生成しました: \(workflow.name)\n\nJSON:\n\(jsonString)\n\n使い方: ショートカット App にコピー → JSON を貼り付け → 実行"
        )
        
        let detail = successPayload(
            result: summary,
            extras: [
                "json": jsonString,
                "workflow_name": workflow.name,
                "action_count": workflow.actions.count,
                "action_type": actionType
            ]
        )
        
        return CanonicalToolResult(success: true, summary: summary, detail: detail)
    }
    
    // MARK: - Export (导出 .shortcut 文件)
    
    private static func exportCanonical(_ args: [String: Any]) async throws -> CanonicalToolResult {
        guard let json = args["json"] as? String, !json.isEmpty else {
            return shortcutsFailure(
                summary: tr("缺少 JSON 内容。", "Missing JSON content.", "JSON 内容がありません。"),
                detail: tr("缺少 json 参数", "Missing 'json' parameter", "json パラメータがありません"),
                errorCode: "JSON_MISSING"
            )
        }
        
        let filename = stringArg(args["filename"]) ?? "shortcut-automation.shortcut"
        
        #if os(iOS)
        let documentURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(filename)
        
        do {
            try json.write(to: documentURL, atomically: true, encoding: .utf8)
            
            let shareActivity = UIActivityViewController(
                activityItems: [documentURL],
                applicationActivities: nil
            )
            
            let summary = tr(
                "快捷指令文件已生成: \(filename)\n请使用系统分享功能导入到快捷指令 App。",
                "Shortcut file generated: \(filename)\nUse system share to import into the Shortcuts app.",
                "ショートカットファイルが生成されました: \(filename)\nシステム共有機能でショートカット App にインポートしてください。"
            )
            
            let detail = successPayload(
                result: summary,
                extras: [
                    "file_url": documentURL.absoluteString,
                    "filename": filename,
                    "file_size": FileManager.default.attributesOfItem(atPath: documentURL.path)[.size] as? Int ?? 0
                ]
            )
            return CanonicalToolResult(success: true, summary: summary, detail: detail)
        } catch {
            return shortcutsFailure(
                summary: tr("导出失败: \(error.localizedDescription)", "Export failed: \(error.localizedDescription)", "エクスポート失敗: \(error.localizedDescription)"),
                detail: tr("文件写入失败", "File write failed", "ファイル書き込み失敗"),
                errorCode: "EXPORT_FAILED"
            )
        }
        #else
        return shortcutsFailure(
            summary: tr("当前平台不支持导出。", "Export not supported on this platform.", "このプラットフォームではエクスポートに対応していません。"),
            detail: tr("仅 iOS 支持快捷指令导出", "Only iOS supports Shortcuts export", "iOS のみショートカットエクスポートに対応"),
            errorCode: "PLATFORM_UNSUPPORTED"
        )
        #endif
    }
    
    // MARK: - Copy to Clipboard
    
    private static func copyCanonical(_ args: [String: Any]) async throws -> CanonicalToolResult {
        guard let json = args["json"] as? String, !json.isEmpty else {
            return shortcutsFailure(
                summary: tr("缺少 JSON 内容。", "Missing JSON content.", "JSON 内容がありません。"),
                detail: tr("缺少 json 参数", "Missing 'json' parameter", "json パラメータがありません"),
                errorCode: "JSON_MISSING"
            )
        }
        
        #if os(iOS)
        UIPasteboard.general.string = json
        let summary = tr(
            "已复制到剪贴板\n\n\(json)\n\n前往快捷指令 App 粘贴即可。",
            "Copied to clipboard\n\n\(json)\n\nPaste in the Shortcuts app.",
            "クリップボードにコピーしました\n\n\(json)\n\nショートカット App に貼り付けてください。"
        )
        let detail = successPayload(result: summary, extras: ["json": json])
        return CanonicalToolResult(success: true, summary: summary, detail: detail)
        #else
        return shortcutsFailure(
            summary: tr("当前平台不支持复制。", "Clipboard not supported on this platform.", "このプラットフォームではコピーに対応していません。"),
            detail: tr("仅 iOS 支持剪贴板操作", "Only iOS supports clipboard operations", "iOS のみクリップボード操作に対応"),
            errorCode: "PLATFORM_UNSUPPORTED"
        )
        #endif
    }
    
    // MARK: - Private Helpers
    
    private static func shortcutsFailure(
        summary: String,
        detail: String,
        errorCode: String
    ) -> CanonicalToolResult {
        CanonicalToolResult(
            success: false,
            summary: summary,
            detail: failurePayload(error: detail, extras: ["error_code": errorCode]),
            errorCode: errorCode
        )
    }
    
    private static func stringArg(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    
    private static func arrayArg(_ value: Any?) -> [String]? {
        if let array = value as? [String] {
            return array
        }
        if let string = value as? String {
            return [string]
        }
        return nil
    }
    
    private static func doubleArg(_ value: Any?) -> Double? {
        switch value {
        case let double as Double: return double
        case let int as Int: return Double(int)
        case let number as NSNumber: return number.doubleValue
        case let string as String:
            return Double(string.trimmingCharacters(in: .whitespacesAndNewlines))
        default: return nil
        }
    }
    
    private static func boolArg(_ value: Any?) -> Bool? {
        switch value {
        case let bool as Bool: return bool
        case let number as NSNumber: return number.boolValue
        case let string as String:
            let normalized = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if ["true", "yes", "1", "on", "开", "开启"].contains(normalized) { return true }
            if ["false", "no", "0", "off", "关", "关闭"].contains(normalized) { return false }
            return nil
        default: return nil
        }
    }
}
