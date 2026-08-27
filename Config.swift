// 云端API配置
// 注意: 把 APIKey 替换成你自己的网关key (config.yaml 里的 aquaaigateway api_key)
// 生产环境建议放 Keychain，这里简化直接填
struct Config {
    static let gateway = "https://api.ltzy.top/v1"
    static let asrModel = "SenseVoiceSmall"
    static let llmModel = "openai/gpt-oss-120b"
    static var apiKey: String = "sk-vw50kkslzpy"
}

struct LangOption: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let code: String?   // nil = 自动检测
    static let all = [
        LangOption(name: "自动检测", code: nil),
        LangOption(name: "英语", code: "en"),
        LangOption(name: "日语", code: "ja"),
        LangOption(name: "韩语", code: "ko"),
        LangOption(name: "法语", code: "fr"),
        LangOption(name: "德语", code: "de"),
        LangOption(name: "西班牙语", code: "es"),
        LangOption(name: "俄语", code: "ru"),
    ]
}
