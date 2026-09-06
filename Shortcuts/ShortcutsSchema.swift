import Foundation

// MARK: - iOS Shortcuts JSON Schema
//
// 定义了 iOS 快捷指令(Shortcuts)自动化 JSON 的完整数据结构。
// 核心变化: OpenClaw 原本是硬编码操控设备(直接调用 EventKit/ContactsKit 等 API),
// 现在改为输出符合 iOS Shortcuts 规范的 JSON 串, 让 iOS 系统识别并执行。
//
// 参考文档: https://developer.apple.com/documentation/shortcuts/
// 快捷指令 JSON 格式 (actionlist) 参考自 Apple Shortcuts 插件自动化导出格式。
//
// 设计原则:
//   1. 所有动作都序列化为 JSON, 由 iOS Shortcuts 框架解释执行
//   2. JSON 输出到系统剪贴板或写入临时文件, 用户可一键导入 Shortcuts App
//   3. 保留 OpenClaw 的工具路由逻辑, 只是执行层从硬编码改为 JSON 输出

// MARK: - ShortcutAction (单个动作)

/// iOS Shortcuts 的单个动作。
/// 对应快捷指令编辑器中的一个操作块。
struct ShortcutAction: Codable, Equatable {
    let uuid: String
    let title: String
    let dialog: String
    let parameters: [String: AnyCodable]
    
    init(
        uuid: String = UUID().uuidString,
        title: String,
        dialog: String = "",
        parameters: [String: AnyCodable] = [:]
    ) {
        self.uuid = uuid
        self.title = title
        self.dialog = dialog
        self.parameters = parameters
    }
    
    /// 转换为 iOS Shortcuts 原生 JSON 字典
    func toDictionary() -> [String: Any] {
        var result: [String: Any] = [
            "UUID": uuid,
            "ActionTitle": title
        ]
        if !dialog.isEmpty {
            result["ActionDialog"] = dialog
        }
        if !parameters.isEmpty {
            var params: [String: Any] = [:]
            for (key, value) in parameters {
                params[key] = value.toAny()
            }
            result["Parameters"] = params
        }
        return result
    }
}

// MARK: - ShortcutWorkflow (完整快捷指令)

/// 一个完整的 iOS 快捷指令自动化定义。
/// 这是整个 Shortcuts JSON 的根对象。
struct ShortcutWorkflow: Codable, Equatable {
    let uuid: String
    let name: String
    let actions: [ShortcutAction]
    let isWorkflow: Bool
    let folderType: String
    let runAtLaunch: Bool
    let runInHidden: Bool
    
    init(
        uuid: String = UUID().uuidString,
        name: String,
        actions: [ShortcutAction] = [],
        isWorkflow: Bool = true,
        folderType: String = "default",
        runAtLaunch: Bool = false,
        runInHidden: Bool = false
    ) {
        self.uuid = uuid
        self.name = name
        self.actions = actions
        self.isWorkflow = isWorkflow
        self.folderType = folderType
        self.runAtLaunch = runAtLaunch
        self.runInHidden = runInHidden
    }
    
    /// 转换为 iOS Shortcuts actionlist JSON 格式 (可直接导入快捷指令 App)
    func toShortcutsJSON() -> [String: Any] {
        var actionsDict: [[String: Any]] = []
        for action in actions {
            actionsDict.append(action.toDictionary())
        }
        
        var parameters: [String: Any] = [
            "UUID": uuid,
            "Actions": actionsDict,
            "ActionProperties": [:],
            "Name": name
        ]
        
        if isWorkflow {
            parameters["IsWorkflow"] = true
        }
        if !folderType.isEmpty {
            parameters["FolderType"] = folderType
        }
        if runAtLaunch {
            parameters["RunAtLaunch"] = true
        }
        
        return [
            "Parameters": parameters,
            "DocumentTypeIdentifier": "com.apple.shortcuts.actionlist",
            "ApplicationVersion": "2.5.2",
            "CFBundleVersion": "956",
            "WFWorkflowMinimumClientVersionString": "559",
            "WFWorkflowMinimumClientVersion": 559,
            "WFWorkflowIcon": [
                "Kind": "color",
                "Color": 4
            ],
            "WFWorkflowActions": actionsDict
        ]
    }
    
    /// 序列化为格式化 JSON 字符串 (用于剪贴板/文件导出)
    func toJSONString(prettyPrinted: Bool = true) -> String {
        let dict = toShortcutsJSON()
        guard let data = try? JSONSerialization.data(
            withJSONObject: dict,
            options: prettyPrinted ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        ) else {
            return "{}"
        }
        return String(data: data, encoding: .utf8) ?? "{}"
    }
    
    /// 序列化为紧凑 JSON 字符串 (用于网络传输)
    func toCompactJSONString() -> String {
        toJSONString(prettyPrinted: false)
    }
}

// MARK: - AnyCodable (JSON 类型安全包装)

/// 类型安全的 JSON 值包装器, 支持 String/Int/Double/Bool/Array/Dictionary。
/// 用于 ShortcutAction.parameters 中灵活存储不同类型的参数值。
struct AnyCodable: Codable, Equatable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            let codableDict = dict.mapValues { AnyCodable($0) }
            try container.encode(codableDict)
        default:
            try container.encode(String(describing: value))
        }
    }
    
    func toAny() -> Any {
        return value
    }
    
    static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        lhs.value as? NSString == rhs.value as? NSString
            || lhs.value as? NSNumber == rhs.value as? NSNumber
            || lhs.value is NSNull && rhs.value is NSNull
    }
}

// MARK: - ShortcutActionBuilder (动作构造器)

/// 链式构造器, 用于优雅地构建 ShortcutWorkflow。
///
/// 示例:
/// ```swift
/// let workflow = ShortcutWorkflowBuilder(name: "发送消息")
///     .say("你好, 我是 AI 助手")
///     .sendSMS(to: "13800138000", body: "测试消息")
///     .build()
/// ```
struct ShortcutWorkflowBuilder {
    private var name: String
    private var actions: [ShortcutAction] = []
    private var runAtLaunch: Bool = false
    private var runInHidden: Bool = false
    
    init(name: String) {
        self.name = name
    }
    
    // MARK: - 核心动作
    
    /// 朗读文本
    func say(_ text: String, language: String = "zh-Hans", voice: String? = nil) -> Self {
        var params: [String: AnyCodable] = [
            "Text": AnyCodable([
                "Value": text,
                "Type": "String",
                "Version": 1
            ]),
            "SpeakLanguage": AnyCodable(language),
            "UseFillerWords": AnyCodable(true)
        ]
        if let voice {
            params["Voice"] = AnyCodable(voice)
        }
        actions.append(ShortcutAction(title: "Say Text", parameters: params))
        return self
    }
    
    /// 设置变量
    func setVariable(_ name: String, value: Any) -> Self {
        let params: [String: AnyCodable] = [
            "Target": AnyCodable(name),
            "Value": AnyCodable(value)
        ]
        actions.append(ShortcutAction(title: "Set Variable", parameters: params))
        return self
    }
    
    /// 显示警报
    func showAlert(_ message: String, title: String? = nil) -> Self {
        var params: [String: AnyCodable] = [
            "Content": AnyCodable([
                "Value": message,
                "Type": "String",
                "Version": 1
            ])
        ]
        if let title {
            params["Title"] = AnyCodable(title)
        }
        actions.append(ShortcutAction(title: "Show Alert", parameters: params))
        return self
    }
    
    /// 打开 URL
    func openURL(_ url: String) -> Self {
        let params: [String: AnyCodable] = [
            "Target": AnyCodable(url)
        ]
        actions.append(ShortcutAction(title: "Open URL", parameters: params))
        return self
    }
    
    /// 打开应用
    func openApp(_ bundleIdentifier: String) -> Self {
        let params: [String: AnyCodable] = [
            "Target": AnyCodable([
                "Type": "Application",
                "Value": bundleIdentifier
            ])
        ]
        actions.append(ShortcutAction(title: "Open App", parameters: params))
        return self
    }
    
    // MARK: - 通信类动作
    
    /// 发送短信
    func sendSMS(to: [String], body: String) -> Self {
        let params: [String: AnyCodable] = [
            "Recipients": AnyCodable(to),
            "Body": AnyCodable(body),
            "SendToContacts": AnyCodable(false)
        ]
        actions.append(ShortcutAction(title: "Send Message", parameters: params))
        return self
    }
    
    /// 拨打电话
    func callPhone(_ number: String) -> Self {
        let params: [String: AnyCodable] = [
            "Number": AnyCodable(number),
            "Confirm": AnyCodable(false)
        ]
        actions.append(ShortcutAction(title: "Call Phone", parameters: params))
        return self
    }
    
    /// 发送邮件
    func sendEmail(to: [String], subject: String, body: String) -> Self {
        let params: [String: AnyCodable] = [
            "Recipients": AnyCodable(to),
            "Subject": AnyCodable(subject),
            "Body": AnyCodable(body)
        ]
        actions.append(ShortcutAction(title: "Send Email", parameters: params))
        return self
    }
    
    // MARK: - 日历/提醒类动作
    
    /// 创建日历事件
    func addCalendarEvent(
        title: String,
        startDate: String,
        endDate: String,
        location: String? = nil,
        notes: String? = nil,
        calendar: String? = nil
    ) -> Self {
        var params: [String: AnyCodable] = [
            "Title": AnyCodable(title),
            "StartDate": AnyCodable(startDate),
            "EndDate": AnyCodable(endDate),
            "Calendar": AnyCodable(calendar ?? "iCloud")
        ]
        if let location {
            params["Location"] = AnyCodable(location)
        }
        if let notes {
            params["Notes"] = AnyCodable(notes)
        }
        actions.append(ShortcutAction(title: "Add Calendar Event", parameters: params))
        return self
    }
    
    /// 创建提醒事项
    func addReminder(
        title: String,
        dueDate: String? = nil,
        notes: String? = nil
    ) -> Self {
        var params: [String: AnyCodable] = [
            "Title": AnyCodable(title),
            "List": AnyCodable("Reminders")
        ]
        if let dueDate {
            params["DueDate"] = AnyCodable(dueDate)
        }
        if let notes {
            params["Notes"] = AnyCodable(notes)
        }
        actions.append(ShortcutAction(title: "Add Reminder", parameters: params))
        return self
    }
    
    // MARK: - 系统类动作
    
    /// 设置系统音量
    func setVolume(_ level: Double) -> Self {
        let params: [String: AnyCodable] = [
            "Level": AnyCodable(level),
            "Muted": AnyCodable(false)
        ]
        actions.append(ShortcutAction(title: "Set Volume", parameters: params))
        return self
    }
    
    /// 设置亮度
    func setBrightness(_ level: Double) -> Self {
        let params: [String: AnyCodable] = [
            "Level": AnyCodable(level)
        ]
        actions.append(ShortcutAction(title: "Set Brightness", parameters: params))
        return self
    }
    
    /// 开关 Wi-Fi
    func setWiFi(enabled: Bool) -> Self {
        let params: [String: AnyCodable] = [
            "Enabled": AnyCodable(enabled)
        ]
        actions.append(ShortcutAction(title: "Set Wi-Fi", parameters: params))
        return self
    }
    
    /// 开关蓝牙
    func setBluetooth(enabled: Bool) -> Self {
        let params: [String: AnyCodable] = [
            "Enabled": AnyCodable(enabled)
        ]
        actions.append(ShortcutAction(title: "Set Bluetooth", parameters: params))
        return self
    }
    
    /// 开关飞行模式
    func setAirplaneMode(enabled: Bool) -> Self {
        let params: [String: AnyCodable] = [
            "Enabled": AnyCodable(enabled)
        ]
        actions.append(ShortcutAction(title: "Set Airplane Mode", parameters: params))
        return self
    }
    
    /// 开关手电筒
    func setFlashlight(enabled: Bool) -> Self {
        let params: [String: AnyCodable] = [
            "Enabled": AnyCodable(enabled)
        ]
        actions.append(ShortcutAction(title: "Set Flashlight", parameters: params))
        return self
    }
    
    /// 震动反馈
    func vibrate() -> Self {
        let params: [String: AnyCodable] = [:]
        actions.append(ShortcutAction(title: "Vibrate", parameters: params))
        return self
    }
    
    /// 播放声音
    func playSound(_ name: String) -> Self {
        let params: [String: AnyCodable] = [
            "Sound": AnyCodable(name)
        ]
        actions.append(ShortcutAction(title: "Play Sound", parameters: params))
        return self
    }
    
    // MARK: - 数据操作动作
    
    /// 读取剪贴板
    func getClipboard() -> Self {
        let params: [String: AnyCodable] = [:]
        actions.append(ShortcutAction(title: "Get Clipboard", parameters: params))
        return self
    }
    
    /// 设置剪贴板
    func setClipboard(_ text: String) -> Self {
        let params: [String: AnyCodable] = [
            "Text": AnyCodable(text)
        ]
        actions.append(ShortcutAction(title: "Set Clipboard", parameters: params))
        return self
    }
    
    /// 打开备忘录
    func createNote(_ title: String, body: String) -> Self {
        let params: [String: AnyCodable] = [
            "Title": AnyCodable(title),
            "Body": AnyCodable(body)
        ]
        actions.append(ShortcutAction(title: "Create Note", parameters: params))
        return self
    }
    
    // MARK: - 流程控制
    
    /// 条件判断
    func ifCondition(_ expression: String, thenActions: [ShortcutAction], elseActions: [ShortcutAction] = []) -> Self {
        let conditionUUID = UUID().uuidString
        actions.append(ShortcutAction(
            uuid: conditionUUID,
            title: "If",
            dialog: expression,
            parameters: [
                "Condition": AnyCodable(expression),
                "ThenActions": AnyCodable(thenActions.map { $0.toDictionary() }),
                "ElseActions": AnyCodable(elseActions.map { $0.toDictionary() })
            ]
        ))
        return self
    }
    
    /// 重复循环
    func repeatForEach(_ collection: Any, body: [ShortcutAction]) -> Self {
        let params: [String: AnyCodable] = [
            "Collection": AnyCodable(collection),
            "BodyActions": AnyCodable(body.map { $0.toDictionary() })
        ]
        actions.append(ShortcutAction(title: "Repeat For Each", parameters: params))
        return self
    }
    
    /// 等待指定秒数
    func wait(seconds: Double) -> Self {
        let params: [String: AnyCodable] = [
            "Duration": AnyCodable(seconds)
        ]
        actions.append(ShortcutAction(title: "Wait", parameters: params))
        return self
    }
    
    /// 运行脚本
    func runScript(_ script: String, language: String = "javascript") -> Self {
        let params: [String: AnyCodable] = [
            "Source": AnyCodable(script),
            "Language": AnyCodable(language),
            "Output": AnyCodable("Output")
        ]
        actions.append(ShortcutAction(title: "Run Script", parameters: params))
        return self
    }
    
    // MARK: - 构建
    
    func runAtLaunch(_ enabled: Bool) -> Self {
        self.runAtLaunch = enabled
        return self
    }
    
    func runInHidden(_ enabled: Bool) -> Self {
        self.runInHidden = enabled
        return self
    }
    
    func build() -> ShortcutWorkflow {
        ShortcutWorkflow(
            name: name,
            actions: actions,
            isWorkflow: true,
            folderType: "default",
            runAtLaunch: runAtLaunch,
            runInHidden: runInHidden
        )
    }
}

// MARK: - ShortcutActionCatalog (常用动作模板)

/// 常用动作模板集合, 供 Agent 编排器直接引用。
enum ShortcutActionCatalog {
    
    /// 常用动作标题常量
    enum Titles {
        static let say = "Say Text"
        static let sendSMS = "Send Message"
        static let callPhone = "Call Phone"
        static let sendEmail = "Send Email"
        static let addCalendarEvent = "Add Calendar Event"
        static let addReminder = "Add Reminder"
        static let openURL = "Open URL"
        static let openApp = "Open App"
        static let showAlert = "Show Alert"
        static let setVariable = "Set Variable"
        static let getClipboard = "Get Clipboard"
        static let setClipboard = "Set Clipboard"
        static let createNote = "Create Note"
        static let setVolume = "Set Volume"
        static let setBrightness = "Set Brightness"
        static let setWiFi = "Set Wi-Fi"
        static let setBluetooth = "Set Bluetooth"
        static let setAirplaneMode = "Set Airplane Mode"
        static let setFlashlight = "Set Flashlight"
        static let vibrate = "Vibrate"
        static let playSound = "Play Sound"
        static let ifCondition = "If"
        static let repeatForEach = "Repeat For Each"
        static let wait = "Wait"
        static let runScript = "Run Script"
    }
}
