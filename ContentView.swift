import SwiftUI
import AVKit
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var videoURL: URL?
    @State private var lang = LangOption.all[0]
    @State private var log: [String] = []
    @State private var busy = false
    @State private var resultURL: URL?
    @State private var showPicker = false

    var body: some View {
        NavigationView {
            Form {
                Section("1. 视频") {
                    Button(action: { showPicker = true }) {
                        Label(videoURL?.lastPathComponent ?? "选择视频", systemImage: "film")
                    }
                    if let url = videoURL {
                        Text(url.lastPathComponent).font(.caption).foregroundColor(.gray)
                    }
                }
                Section("2. 原语言") {
                    Picker("语言", selection: $lang) {
                        ForEach(LangOption.all) { Text($0.name).tag($0) }
                    }
                }
                Section("3. 生成") {
                    Button(action: run) {
                        if busy { ProgressView().frame(maxWidth: .infinity) }
                        else { Text("▶ 生成双语字幕").frame(maxWidth: .infinity) }
                    }.disabled(busy || videoURL == nil)
                }
                Section("日志") {
                    ForEach(log, id: \.self) { Text($0).font(.caption2).foregroundColor(.secondary) }
                }
                if let url = resultURL {
                    Section("结果") {
                        Link("打开字幕文件 (.srt)", destination: url)
                        Button("保存到文件App") { saveToFiles(url) }
                    }
                }
            }
            .navigationTitle("双语言字幕")
        }
        .sheet(isPresented: $showPicker) {
            VideoPicker(url: $videoURL)
        }
    }

    func run() {
        guard let url = videoURL else { return }
        busy = true; log = ["开始..."]
        Task {
            do {
                let asset = AVURLAsset(url: url)
                let dur = try await asset.load(.duration).seconds
                log.append("上传识别中...")
                let text = try await APIClient.shared.transcribe(videoURL: url) { _ in }
                log.append("识别: \(text.prefix(40))...")
                let sents = SRTBuilder.splitSentences(text)
                log.append("翻译 \(sents.count) 句...")
                let tr = try await APIClient.shared.translate(segments: sents)
                let srt = SRTBuilder.build(original: text, translated: tr, totalSeconds: dur)
                let out = FileManager.default.temporaryDirectory
                    .appendingPathComponent((url.deletingPathExtension().lastPathComponent) + ".bilingual.srt")
                try srt.write(to: out, atomically: true, encoding: .utf8)
                await MainActor.run {
                    resultURL = out
                    log.append("✅ 完成: \(out.lastPathComponent)")
                    busy = false
                }
            } catch {
                await MainActor.run {
                    log.append("❌ \(error.localizedDescription)")
                    busy = false
                }
            }
        }
    }

    func saveToFiles(_ url: URL) {
        // 复制到Documents便于在Files app看到
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dst = docs.appendingPathComponent(url.lastPathComponent)
        try? FileManager.default.removeItem(at: dst)
        try? FileManager.default.copyItem(at: url, to: dst)
        log.append("已保存到: \(dst.lastPathComponent)")
    }
}

struct VideoPicker: UIViewControllerRepresentable {
    @Binding var url: URL?
    @Environment(\.dismiss) var dismiss
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.mediaTypes = ["public.movie"]
        p.delegate = context.coordinator
        return p
    }
    func updateUIViewController(_ c: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: VideoPicker
        init(_ p: VideoPicker) { parent = p }
        func imagePickerController(_ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let u = info[.mediaURL] as? URL { parent.url = u }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
