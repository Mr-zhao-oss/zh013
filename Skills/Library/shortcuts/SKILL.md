---
name: Shortcuts
name-zh: 快捷指令
description: '生成 iOS 快捷指令 JSON, 用户可一键导入执行。无需系统写权限, 适合替代直接操控设备。'
version: "1.0.0"
icon: bolt.fill
disabled: false
type: device
activation: prompt
chip_prompt: "帮我创建一个关闭蓝牙并降低亮度的快捷指令"
chip_label: "快捷指令"

triggers:
  - 快捷指令
  - shortcut
  - 自动化
  - 自动执行
  - 无需权限
  - 一键执行
  - 生成指令
  - 导入执行

allowed-tools:
  - shortcuts-generate
  - shortcuts-export
  - shortcuts-copy

side_effects:
  level: read
  tools:
    shortcuts-generate:
      level: read
    shortcuts-export:
      level: read
    shortcuts-copy:
      level: read

examples:
  - query: "帮我创建一个关闭蓝牙并降低亮度的快捷指令"
    scenario: "多动作组合"
  - query: "生成一个给我发条消息的快捷指令"
    scenario: "发送短信"
  - query: "创建一个明天下午两点开会的日历快捷指令"
    scenario: "创建日历事件"
  - query: "帮我做个每天早上朗读新闻的快捷指令"
    scenario: "朗读 + 自动化"
---

# 快捷指令

将用户意图转换为 iOS 快捷指令 JSON, 用户可一键导入快捷指令 App 执行。
与直接操控设备的区别: 本 skill 不写入系统数据, 只生成可导入的 JSON 串。

## 核心原则

1. **生成 JSON, 不直接执行**: 所有写入类操作 (创建日历/通讯录/短信等) 都生成 Shortcuts JSON, 用户导入后由系统执行。
2. **无需系统权限**: 日历、通讯录、短信写入都不需要 App 的系统写权限。
3. **多动作组合**: 一个快捷指令可以包含多个动作 (如: 关蓝牙 + 降亮度 + 设勿扰模式)。

## 工具选择

- 生成新的快捷指令 → 调 `shortcuts-generate`
- 复制 JSON 到剪贴板 → 调 `shortcuts-copy`
- 导出为 .shortcut 文件 → 调 `shortcuts-export`

## 动作类型 (action_type)

| action_type | 说明 | 必需参数 |
|---|---|---|
| say | 朗读文本 | text |
| send_sms | 发送短信 | to, body |
| call | 拨打电话 | number |
| email | 发送邮件 | to, subject, body |
| calendar_event | 创建日历事件 | title, start, end |
| reminder | 创建提醒 | title, (due_date) |
| set_volume | 设置音量 | level (0.0-1.0) |
| set_brightness | 设置亮度 | level (0.0-1.0) |
| set_wifi | 开关 Wi-Fi | enabled (true/false) |
| set_bluetooth | 开关蓝牙 | enabled (true/false) |
| set_flashlight | 开关手电筒 | enabled (true/false) |
| set_airplane_mode | 开关飞行模式 | enabled (true/false) |
| open_url | 打开链接 | url |
| open_app | 打开应用 | bundle_id |
| show_alert | 显示通知 | message |
| create_note | 创建备忘录 | title, body |
| set_clipboard | 设置剪贴板 | text |
| wait | 等待秒数 | seconds |
| vibrate | 震动 | (无) |
| play_sound | 播放声音 | name |

## 调用格式

用户意图: "帮我关蓝牙并降低亮度"

<tool_call>
{"name": "shortcuts-generate", "arguments": {"action_type": "set_bluetooth", "params": {"enabled": false}}}
</tool_call>