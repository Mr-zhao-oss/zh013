# 双语言字幕 iOS App —— 成品 .ipa 获取指南

你的情况：**只有 Windows 电脑 + iPhone（轻松签只签名，不能编译）**。
→ 用 **GitHub Actions 免费云 Mac** 替你编译出未签名 .ipa，再用轻松签签名装机。
全程浏览器操作，不用装 Xcode，不用有自己的 Mac。

## 步骤（约5分钟）

1. 注册 GitHub 账号：https://github.com （免费）
2. 新建仓库：右上角 + → New repository → 名字随便（如 `dualsub-ios`）→ 选 Public 或 Private 都行 → Create
3. 上传代码：进仓库 → Add file → Upload files → 把本目录 `DualSubiOS/` 下**所有文件**拖进去（含 `.github` 隐藏文件夹！）→ Commit
4. 触发构建：仓库顶部 **Actions** 标签 → 左侧 `Build DualSubiOS IPA` → 右侧 **Run workflow** → 确认
5. 等约 2~3 分钟，绿勾后点进去 → **Artifacts** 区下载 `DualSubiOS-unsigned-ipa`（就是 .ipa 文件）
6. 把下载的 .ipa 用 AirDrop/网盘/数据线传到 iPhone → 用 **轻松签** 打开 → 导入你的证书/描述文件 → 签名 → 安装
7. iPhone：设置 → 通用 → VPN与设备管理 → 信任你的证书

> 免费证书约7天有效，到期重签即可（重新下载 ipa 或保留原包重签）

## 项目里已包含什么
- 全部 Swift 源码（API key 已填 `sk-vw50kkslzpy`，免费网关自动轮换）
- `project.pbxproj` / `DualSubiOS.xcscheme` —— Xcode 工程（scheme 已对齐）
- `.github/workflows/build.yml` —— 云端 Mac 编译脚本（未签名出 ipa）
- `exportOptions.plist` / `build_ipa.sh` —— 备用（有 Mac 时本地一条命令出包）

## 限制（诚实）
- iPhone 端**不把字幕烧进视频**（iOS 无 ffmpeg），只导出双语 .srt（上原文下中文）
- 播放：VLC / Infuse / nPlayer 等加载 .srt 即可双语言显示
- 云端 ASR 对耳语/ASMR 非语言声音识别弱，正常说话最佳
- 需联网（直连 api.ltzy.top，不需你自己有服务器）

## 文件清单
- DualSubiOSApp.swift / ContentView.swift / Config.swift / APIClient.swift / SRTBuilder.swift
- Info.plist / project.pbxproj / DualSubiOS.xcscheme / exportOptions.plist
- .github/workflows/build.yml / build_ipa.sh / README.md
