import Foundation

struct SRTBuilder {
    // 把整段文本按标点/换行切成句子, 在总时长内平均分配时间轴
    static func build(original: String, translated: [String], totalSeconds: Double) -> String {
        let sentences = splitSentences(original)
        guard !sentences.isEmpty else { return "" }
        let per = totalSeconds / Double(sentences.count)
        var out = ""
        for (i, sent) in sentences.enumerated() {
            let start = Double(i) * per
            let end = (i + 1) * per
            let tr = i < translated.count ? translated[i] : ""
            out += "\(i+1)\n"
            out += "\(fmt(start)) --> \(fmt(end))\n"
            out += "\(sent)\n"
            if !tr.isEmpty { out += "\(tr)\n" }
            out += "\n"
        }
        return out
    }

    static func splitSentences(_ text: String) -> [String] {
        let cleaned = text.replacingOccurrences(of: "\n+", with: " ", options: .regularExpression)
                          .trimmingCharacters(in: .whitespaces)
        let parts = cleaned.components(separatedBy: CharacterSet(charactersIn: ".。!?！？…,，;；"))
                          .map { $0.trimmingCharacters(in: .whitespaces) }
                          .filter { !$0.isEmpty }
        return parts.isEmpty ? [cleaned] : parts
    }

    static func fmt(_ sec: Double) -> String {
        let ms = Int(round(sec*1000))
        let h = ms/3600000, m = (ms%3600000)/60000, s = (ms%60000)/1000, r = ms%1000
        return String(format: "%02d:%02d:%02d,%03d", h,m,s,r)
    }
}
