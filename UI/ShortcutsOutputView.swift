import SwiftUI
import UniformTypeIdentifiers

// MARK: - Shortcuts Output View
//
// 显示生成的 iOS 快捷指令 JSON, 支持:
//   1. 预览 JSON 内容
//   2. 复制到剪贴板
//   3. 分享为 .shortcut 文件
//   4. 用快捷指令 App 打开
//
// 适配手机屏幕: 全宽布局, 底部操作栏固定, 内容区可滚动。

struct ShortcutsOutputView: View {
    let workflow: ShortcutWorkflow
    let onClose: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @State private var showCopyConfirmation = false
    @State private var showShareSheet = false
    @State private var copiedMessage = ""
    @State private var copiedTimeout: Task<Void, Never>?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // ── 标题区 ──
                headerView
                
                // ── JSON 内容区 ──
                ScrollView {
                    jsonContentView
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                }
                
                // ── 底部操作栏 ──
                actionBar
            }
            .background(Theme.background.primary)
            .navigationTitle("快捷指令")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .accessibilityLabel(Text("关闭"))
                }
            }
        }
        .alert("已复制", isPresented: $showCopyConfirmation) {
            Button("确定") { }
        } message: {
            Text(copiedMessage)
        }
        .sheet(isPresented: $showShareSheet) {
            shareSheet
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                // 从其他 App 回来时刷新
            }
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack(spacing: 12) {
            // 图标
            Image(systemName: "bolt.fill")
                .font(.system(size: 24))
                .foregroundStyle(.yellow)
                .frame(width: 44, height: 44)
                .background(
                    Color.yellow.opacity(0.15),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
            
            // 信息
            VStack(alignment: .leading, spacing: 2) {
                Text(workflow.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.text.primary)
                
                Text("\(workflow.actions.count) 个动作")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text.secondary)
            }
            
            Spacer()
            
            // 打开快捷指令 App
            Button {
                openShortcutsApp()
            } label: {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.blue)
            }
            .accessibilityLabel(Text("打开快捷指令 App"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.background.secondary)
    }
    
    // MARK: - JSON Content
    
    private var jsonContentView: some View {
        let jsonString = workflow.toJSONString(prettyPrinted: true)
        
        return VStack(alignment: .leading, spacing: 12) {
            // JSON 代码块
            ScrollView(.horizontal, showsIndicators: false) {
                Text(jsonString)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Theme.text.primary)
                    .textSelection(.enabled)
                    .padding(14)
            }
            .background(
                Theme.background.tertiary,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: 1)
            )
            
            // 使用说明
            VStack(alignment: .leading, spacing: 8) {
                Text("使用说明")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text.primary)
                
                usageStep(icon: "1.circle.fill", text: "点击「复制」按钮, 复制 JSON 到剪贴板")
                usageStep(icon: "2.circle.fill", text: "打开「快捷指令」App")
                usageStep(icon: "3.circle.fill", text: "点击右上角「+」新建快捷指令")
                usageStep(icon: "4.circle.fill", text: "长按名称 → 粘贴 JSON → 运行")
            }
            .padding(14)
            .background(
                Theme.background.tertiary.opacity(0.5),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
        }
    }
    
    private func usageStep(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(.blue)
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(Theme.text.secondary)
                .lineSpacing(2)
        }
    }
    
    // MARK: - Action Bar
    
    private var actionBar: some View {
        HStack(spacing: 12) {
            // 复制按钮
            Button {
                copyToClipboard()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 16))
                    Text("复制")
                        .font(.system(size: 15, weight: .medium))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    Theme.accent.primary.opacity(0.15),
                    in: Capsule()
                )
                .foregroundStyle(Theme.accent.primary)
            }
            
            // 分享按钮
            Button {
                showShareSheet = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16))
                    Text("分享")
                        .font(.system(size: 15, weight: .medium))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    Theme.accent.primary,
                    in: Capsule()
                )
                .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .padding(.bottom, 4)
        .background(.ultraThinMaterial)
    }
    
    // MARK: - Share Sheet
    
    private var shareSheet: some View {
        let jsonFileURL = generateShortcutFile()
        
        return ShareLink(
            item: jsonFileURL,
            preview: SharePreview(workflow.name, image: Image(systemName: "bolt.fill"))
        ) {
            Label("分享快捷指令", systemImage: "square.and.arrow.up")
                .font(.system(size: 16, weight: .medium))
        }
        .padding()
        .presentationDetents([.medium])
    }
    
    // MARK: - Actions
    
    private func copyToClipboard() {
        let jsonString = workflow.toJSONString(prettyPrinted: true)
        UIPasteboard.general.string = jsonString
        
        copiedMessage = "已复制快捷指令 JSON 到剪贴板\n\n\(jsonString.count) 个字符\n\n前往快捷指令 App 粘贴即可。"
        showCopyConfirmation = true
        
        // 显示剪贴板反馈
        copiedTimeout?.cancel()
        copiedTimeout = Task {
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled {
                // 可添加额外的视觉反馈
            }
        }
    }
    
    private func generateShortcutFile() -> URL {
        let jsonString = workflow.toJSONString(prettyPrinted: true)
        let filename = "\(workflow.name).shortcut"
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(filename)
        
        try? jsonString.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }
    
    private func openShortcutsApp() {
        if let url = URL(string: "shortcuts://"), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Shortcuts Preview Card (聊天内嵌卡片)

/// 聊天消息中嵌入的快捷指令预览卡片
/// 点击后展开完整的 ShortcutsOutputView
struct ShortcutsPreviewCard: View {
    let workflow: ShortcutWorkflow
    let onExpand: () -> Void
    
    var body: some View {
        Button(action: onExpand) {
            HStack(spacing: 12) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.yellow)
                    .frame(width: 40, height: 40)
                    .background(
                        Color.yellow.opacity(0.15),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("快捷指令")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.text.secondary)
                        
                        Text(workflow.name)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Theme.text.primary)
                            .lineLimit(1)
                    }
                    
                    Text("\(workflow.actions.count) 个动作 · 点击导入")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.text.tertiary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.text.tertiary)
            }
            .padding(12)
            .background(
                Theme.background.secondary,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
