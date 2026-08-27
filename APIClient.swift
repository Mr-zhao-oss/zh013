import Foundation

struct APIError: LocalizedError {
    let msg: String
    var errorDescription: String? { msg }
}

final class APIClient {
    static let shared = APIClient()

    // 1) 整段上传音频到云端ASR, 返回文本(无时间戳, 由端上按句切分)
    func transcribe(videoURL: URL, progress: @escaping (Double)->Void) async throws -> String {
        // 先导出为 m4a 音频 (网关ASR期望音频格式)
        let audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("m4a")
        try await exportAudio(from: videoURL, to: audioURL)
        var req = URLRequest(url: URL(string: "\(Config.gateway)/audio/transcriptions")!)
        req.httpMethod = "POST"
        let boundary = "Boundary-\(UUID().uuidString)"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(Config.apiKey)", forHTTPHeaderField: "Authorization")
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/mp4\r\n\r\n".data(using: .utf8)!)
        let data = try Data(contentsOf: audioURL)
        body.append(data)
        body.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(Config.asrModel)\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body
        let (respData, resp) = try await URLSession.shared.upload(for: req, from: body)
        try? FileManager.default.removeItem(at: audioURL)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw APIError(msg: "ASR失败: \((resp as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        guard let json = try? JSONSerialization.jsonObject(with: respData) as? [String:Any],
              let text = (json["text"] as? String) ?? (json["transcript"] as? String) else {
            throw APIError(msg: "ASR返回解析失败")
        }
        return text
    }

    private func exportAudio(from src: URL, to dst: URL) async throws {
        let asset = AVURLAsset(url: src)
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw APIError(msg: "无法导出音频")
        }
        export.outputURL = dst
        export.outputFileType = .m4a
        await export.export()
        if let e = export.error { throw APIError(msg: "音频导出: \(e.localizedDescription)") }
    }

    // 2) 批量翻译 -> 中文
    func translate(segments: [String]) async throws -> [String] {
        let payload: [String:Any] = [
            "model": Config.llmModel,
            "temperature": 0.2,
            "messages": [[
                "role":"user",
                "content": "Translate each segment to Simplified Chinese, natural and concise. " +
                "Output STRICT JSON only: {\"items\":[{\"i\":0,\"t\":\"...\"}]} covering every index.\n\n" +
                JSONStringify(segments.enumerated().map { ["i":$0.offset, "text":$0.element] })
            ]]
        ]
        var req = URLRequest(url: URL(string: "\(Config.gateway)/chat/completions")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(Config.apiKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (respData, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw APIError(msg: "翻译失败: \((resp as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        guard let json = try? JSONSerialization.jsonObject(with: respData) as? [String:Any],
              let choice = (json["choices"] as? [[String:Any]])?.first,
              let msg = choice["message"] as? [String:Any],
              let content = msg["content"] as? String else {
            throw APIError(msg: "翻译返回解析失败")
        }
        let cleaned = content.replacingOccurrences(of: "```json", with: "")
                          .replacingOccurrences(of: "```", with: "").trimmingCharacters(in: .whitespaces)
        guard let start = cleaned.firstIndex(of: "{"),
              let end = cleaned.lastIndex(of: "}") else { return segments }
        let sub = String(cleaned[start...end])
        guard let obj = try? JSONSerialization.jsonObject(with: sub.data(using: .utf8)!) as? [String:Any],
              let items = obj["items"] as? [[String:Any]] else { return segments }
        var out = segments
        for it in items {
            if let i = it["i"] as? Int, let t = it["t"] as? String, i < out.count { out[i] = t }
        }
        return out
    }

    private func JSONStringify(_ obj: Any) -> String {
        guard let d = try? JSONSerialization.data(withJSONObject: obj),
              let s = String(data: d, encoding: .utf8) else { return "[]" }
        return s
    }
}
