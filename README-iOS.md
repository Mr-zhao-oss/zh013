# PhoneClaw for iOS 📱

> OpenClaw 改造版 — 输出 iOS 快捷指令 JSON 串，让 AI 用「快捷指令」操控你的 iPhone

## 🎯 这是什么

把 OpenClaw（桌面端 AI 代理框架）改造成 iOS App。
**核心变化**：AI 不再直接操控设备（需要各种系统权限），
而是输出符合 iOS 快捷指令规范的 JSON 串，用户一键导入「快捷指令 App」执行。

## ✨ 功能

- 🤖 **本地模型推理** — Gemma 4 / MiniCPM-V / Whisper ASR，全部离线
- ⚡ **快捷指令 JSON 输出** — 20+ 种动作（发短信、设亮度、开蓝牙、创建日程…）
- 🎤 **语音输入** — 中文/英文/日文 ASR 语音转文字
- 🖼️ **图片理解** — 拍照提问，本地多模态模型分析
- 📱 **手机适配** — SwiftUI 原生界面，适配各种屏幕

## 🔧 在 Windows 上构建 IPA（无需 Mac）

### 方法：GitHub Actions 云端编译（免费）

#### 第 1 步：把项目推到 GitHub
1. 注册 GitHub 账号（免费）：https://github.com/signup
2. 在 GitHub 新建仓库，比如叫 `phoneclaw-ios`
3. 把 `PhoneClaw/` 文件夹全部推上去：
   ```bash
   cd PhoneClaw
   git init
   git add .
   git commit -m "OpenClaw → PhoneClaw iOS (Shortcuts JSON 版)"
   git branch -M main
   git remote add origin https://github.com/你的用户名/phoneclaw-ios.git
   git push -U origin main
   ```

#### 第 2 步：自动触发构建
推上去后，GitHub 会自动运行 `.github/workflows/build-ipa.yml`，
在 macOS 云主机上编译约 20-40 分钟。

#### 第 3 步：下载 IPA
1. 打开你的 GitHub 仓库页面
2. 点顶部 **「Actions」** 标签
3. 找到最近一次 **「Build iOS IPA」** 运行
4. 滑到底部 **「Artifacts」** → 下载 `PhoneClaw-iOS-IPA`

#### 第 4 步：安装到 iPhone（用 Windows 侧载）
拿到 `.ipa` 文件后，用以下任一工具安装到手机：

| 工具 | 说明 | 下载 |
|---|---|---|
| **Sideloadly**（推荐） | Windows 上最稳的侧载工具 | https://sideloadly.io |
| **AltServer** | 配套 AltStore，自动刷新签名 | https://altstore.io |
| **3uTools** | 国产工具，操作简单 | https://www.3u.com |

**Sideloadly 步骤：**
1. 电脑装 Sideloadly + 最新 iTunes
2. iPhone 用数据线连电脑
3. 打开 Sideloadly，拖入下载的 `.ipa`
4. 输入你的 Apple ID（用于免费开发者签名）
5. 点「Start」→ 等 1-2 分钟装完
6. iPhone 上：设置 → 通用 → VPN与设备管理 → 信任你的开发者证书

⚠️ 免费签名 **7 天后过期**，到期后重连 Sideloadly 刷新即可。

## 🆘 如果构建失败

1. 看 Actions 页面的红色错误日志
2. 常见问题：
   - **依赖下载失败** → 重新触发 Actions（右上角「Re-run jobs」）
   - **内存不足** → GitHub 免费版 7GB RAM，大型模型包可能不够，多试几次
   - **签名错误** → 正常，我们用的就是无签名构建，最后会自动用 fallback 打包

3. 把错误日志发我，我帮你看。

## 📁 项目结构

```
PhoneClaw/
├── Shortcuts/
│   ├── ShortcutsSchema.swift        ← iOS 快捷指令 JSON 定义
│   └── ShortcutsActionHandler.swift ← 替代硬编码，输出 JSON
├── Agent/
│   ├── AgentEngine.swift             ← 引擎主体（原 PhoneClaw）
│   └── AgentOrchestrator.swift       ← OpenClaw 编排逻辑移植
├── UI/
│   ├── ContentView.swift             ← 主界面
│   └── ShortcutsOutputView.swift     ← 快捷指令预览/导出界面
├── Skills/Library/shortcuts/
│   └── SKILL.md                      ← 教 LLM 用快捷指令工具
├── Tools/
│   └── ToolRegistry.swift            ← 已注册 shortcuts 工具
├── .github/workflows/
│   └── build-ipa.yml                 ← 云端自动构建 IPA
└── ExportOptions.plist               ← IPA 导出配置
```

## 📜 核心设计

```
传统 OpenClaw:
  用户消息 → LLM → tool_call → 直接调系统 API（需权限）

改造后 PhoneClaw:
  用户消息 → LLM → tool_call → 生成 iOS Shortcuts JSON → 用户导入执行
```

**优势**：
- ✅ 无需日历/通讯录/短信写入权限
- ✅ 符合 App Store 审核规范
- ✅ 动作可审计、可编辑、可撤销
- ✅ 支持自动化触发（定位/时间/打开 App）
