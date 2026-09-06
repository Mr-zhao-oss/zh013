import Foundation
import Observation

// MARK: - Agent Orchestrator (OpenClaw 代理编排引擎移植)
//
// 从 OpenClaw 的 Gateway/Agent 架构移植核心编排逻辑。
// OpenClaw 原方案: Gateway → Agent → Tool execution (硬编码直接调用)
// PhoneClaw iOS 版: AgentEngine → Orchestrator → Shortcuts JSON 输出
//
// 编排流水线:
//   1. Intent Routing: 识别用户意图, 匹配 skill
//   2. Tool Selection: 根据 skill 的 allowed-tools 选择可用工具
//   3. Parameter Extraction: 从用户消息中提取工具参数
//   4. Execution Planning: 规划执行步骤 (单步/多步)
//   5. Result Aggregation: 聚合工具执行结果
//   6. Response Formatting: 格式化最终回复 (含 Shortcuts JSON)
//
// 与 PhoneClaw 原生 AgentEngine 的关系:
//   - AgentEngine 负责 LLM 推理、模型加载、会话管理
//   - AgentOrchestrator 负责意图路由、工具选择、执行规划
//   - 两者通过 @Observable 状态共享

@Observable
@MainActor
class AgentOrchestrator {
    
    // MARK: - 核心依赖
    
    /// 技能注册表 (含 SKILL.md 定义)
    let skillRegistry: SkillRegistry
    /// 工具注册表 (含 handler 实现)
    let toolRegistry: ToolRegistry
    /// 推理服务 (LLM 调用)
    weak var inference: InferenceService?
    
    // MARK: - 状态
    
    /// 当前激活的技能列表 (按意图匹配)
    var activeSkills: [String] = []
    /// 当前轮次的工具调用链
    var toolCallChain: [ToolCallPlan] = []
    /// 执行状态
    var executionState: ExecutionState = .idle
    /// 最近一次执行的结果
    var lastExecutionResult: ExecutionResult?
    
    // MARK: - 执行状态机
    
    enum ExecutionState: Equatable {
        case idle
        case routing
        case planning
        case executing
        case aggregating
        case done
        case failed(String)
    }
    
    // MARK: - 工具调用计划
    
    struct ToolCallPlan: Identifiable, Equatable {
        let id: UUID
        let toolName: String
        let arguments: [String: Any]
        let skillId: String
        let order: Int
        let dependsOn: [UUID]
        
        init(toolName: String, arguments: [String: Any], skillId: String, order: Int) {
            self.id = UUID()
            self.toolName = toolName
            self.arguments = arguments
            self.skillId = skillId
            self.order = order
            self.dependsOn = []
        }
    }
    
    // MARK: - 执行结果
    
    struct ExecutionResult: Equatable {
        let success: Bool
        let summary: String
        let toolResults: [ToolResult]
        let shortcutsJSON: String?
        let error: String?
        
        struct ToolResult: Equatable {
            let toolName: String
            let success: Bool
            let result: String
            let details: [String: Any]
        }
    }
    
    // MARK: - Init
    
    init(skillRegistry: SkillRegistry, toolRegistry: ToolRegistry) {
        self.skillRegistry = skillRegistry
        self.toolRegistry = toolRegistry
    }
    
    // MARK: - 编排主入口
    
    /// 完整的编排流水线: 意图识别 → 技能匹配 → 工具选择 → 执行规划 → 执行
    func orchestrate(userMessage: String, context: [ChatMessage]) async -> ExecutionResult {
        executionState = .routing
        
        do {
            // 1. 意图路由
            let routedSkills = try await routeIntent(userMessage: userMessage, context: context)
            activeSkills = routedSkills
            
            // 2. 工具选择
            executionState = .planning
            let toolPlan = try planToolCalls(userMessage: userMessage, skills: routedSkills)
            toolCallChain = toolPlan
            
            // 3. 执行
            executionState = .executing
            let results = try await executeToolPlan(toolPlan)
            
            // 4. 聚合
            executionState = .aggregating
            let aggregated = try aggregateResults(results)
            
            executionState = .done
            lastExecutionResult = aggregated
            return aggregated
            
        } catch let error as OrchestrationError {
            executionState = .failed(error.description)
            let result = ExecutionResult(
                success: false,
                summary: error.description,
                toolResults: [],
                shortcutsJSON: nil,
                error: error.description
            )
            lastExecutionResult = result
            return result
        } catch {
            executionState = .failed(error.localizedDescription)
            let result = ExecutionResult(
                success: false,
                summary: "编排失败: \(error.localizedDescription)",
                toolResults: [],
                shortcutsJSON: nil,
                error: error.localizedDescription
            )
            lastExecutionResult = result
            return result
        }
    }
    
    // MARK: - 意图路由
    
    /// 根据用户消息匹配最相关的技能。
    /// 类似 OpenClaw 的 IntentRouter: 基于 triggers 关键词 + LLM 辅助判断。
    private func routeIntent(userMessage: String, context: [ChatMessage]) async throws -> [String] {
        let allSkills = skillRegistry.discoverSkills().filter { $0.isEnabled }
        
        // 策略 1: 基于 triggers 关键词匹配 (快速, 无需 LLM)
        var scoredSkills: [(String, Double)] = []
        for skill in allSkills {
            let score = calculateTriggerScore(
                message: userMessage,
                triggers: skill.metadata.triggers
            )
            if score > 0 {
                scoredSkills.append((skill.id, score))
            }
        }
        
        // 按分数排序, 取 top 3
        let topMatched = scoredSkills
            .sorted { $0.1 > $1.1 }
            .prefix(3)
            .map { $0.0 }
        
        if !topMatched.isEmpty {
            return Array(topMatched)
        }
        
        // 策略 2: 检查是否有 shortcuts 相关的通用意图
        if containsShortcutsIntent(userMessage) {
            return ["shortcuts"]
        }
        
        // 策略 3: 返回空 (由 LLM 自由回答, 不调用工具)
        return []
    }
    
    /// 计算用户消息与 skill triggers 的匹配分数
    private func calculateTriggerScore(message: String, triggers: [String]) -> Double {
        let lowerMessage = message.lowercased()
        var score = 0.0
        for trigger in triggers {
            let lowerTrigger = trigger.lowercased()
            if lowerMessage.contains(lowerTrigger) {
                // 精确匹配给更高分
                if lowerMessage == lowerTrigger {
                    score += 3.0
                } else {
                    score += 1.0 + (Double(trigger.count) / Double(lowerMessage.count))
                }
            }
        }
        return score
    }
    
    /// 判断是否包含快捷指令相关意图
    private func containsShortcutsIntent(_ message: String) -> Bool {
        let lower = message.lowercased()
        let keywords = [
            "快捷指令", "shortcut", "自动化", "自动执行",
            "生成指令", "导入执行", "一键执行",
            "不用权限", "不用权限", "无需权限"
        ]
        return keywords.contains { lower.contains($0) }
    }
    
    // MARK: - 工具调用规划
    
    /// 根据匹配到的技能, 规划工具调用链。
    /// 类似 OpenClaw 的 ToolSelector: 从 skill 的 allowed-tools 中选择。
    private func planToolCalls(userMessage: String, skills: [String]) throws -> [ToolCallPlan] {
        guard !skills.isEmpty else { return [] }
        
        var plans: [ToolCallPlan] = []
        var order = 0
        
        for skillId in skills {
            guard let definition = skillRegistry.getDefinition(skillId) else { continue }
            let allowedTools = definition.metadata.allowedTools
            
            for toolName in allowedTools {
                guard let tool = toolRegistry.find(name: toolName) else { continue }
                
                // 参数提取
                let arguments = extractArguments(
                    toolName: toolName,
                    tool: tool,
                    message: userMessage
                )
                
                // 参数校验
                guard toolRegistry.validatesArguments(arguments, for: toolName) else {
                    PCLog.debug("[Orchestrator] tool '\(toolName)' 参数不完整, 跳过")
                    continue
                }
                
                plans.append(ToolCallPlan(
                    toolName: toolName,
                    arguments: arguments,
                    skillId: skillId,
                    order: order
                ))
                order += 1
            }
        }
        
        return plans
    }
    
    /// 从用户消息中提取工具参数
    private func extractArguments(
        toolName: String,
        tool: RegisteredTool,
        message: String
    ) -> [String: Any] {
        // 根据工具类型提取参数
        switch toolName {
        case "shortcuts-generate":
            return extractShortcutsArguments(message: message)
        case "shortcuts-copy", "shortcuts-export":
            // 这些工具需要前置的 shortcuts-generate 输出
            return [:]
        default:
            return [:]
        }
    }
    
    /// 从用户消息中提取 Shortcuts 参数
    private func extractShortcutsArguments(message: String) -> [String: Any] {
        var params: [String: Any] = [:]
        let lower = message.lowercased()
        
        // 检测动作类型
        if lower.contains("蓝牙") || lower.contains("bluetooth") {
            params["action_type"] = "set_bluetooth"
            params["params"] = ["enabled": !lower.contains("开")]
        } else if lower.contains("亮度") || lower.contains("brightness") {
            params["action_type"] = "set_brightness"
            if let level = extractLevel(message) {
                params["params"] = ["level": level]
            }
        } else if lower.contains("音量") || lower.contains("volume") {
            params["action_type"] = "set_volume"
            if let level = extractLevel(message) {
                params["params"] = ["level": level]
            }
        } else if lower.contains("wifi") || lower.contains("wi-fi") {
            params["action_type"] = "set_wifi"
            params["params"] = ["enabled": !lower.contains("关")]
        } else if lower.contains("手电筒") || lower.contains("闪光灯") {
            params["action_type"] = "set_flashlight"
            params["params"] = ["enabled": !lower.contains("关")]
        } else if lower.contains("短信") || lower.contains("发消息") {
            params["action_type"] = "send_sms"
            params["params"] = ["body": "来自 PhoneClaw 的消息"]
        } else if lower.contains("朗读") || lower.contains("播报") {
            params["action_type"] = "say"
            params["params"] = ["text": "你好，我是 PhoneClaw AI 助手"]
        } else if lower.contains("日历") || lower.contains("日程") || lower.contains("会议") {
            params["action_type"] = "calendar_event"
            params["params"] = [
                "title": "新日程",
                "start": "明天下午两点",
                "end": "明天下午三点"
            ]
        } else if lower.contains("提醒") {
            params["action_type"] = "reminder"
            params["params"] = ["title"] = "新提醒"
        } else {
            params["action_type"] = "show_alert"
            params["params"] = ["message"] = message
        }
        
        return params
    }
    
    /// 从消息中提取级别数值 (0.0-1.0)
    private func extractLevel(_ message: String) -> Double? {
        let numbers = message.matches(of: #"\d+(\.\d+)?"#)
            .compactMap { Double($0) }
        guard let number = numbers.first else { return nil }
        return min(1.0, max(0.0, number / 100.0))
    }
    
    // MARK: - 执行
    
    /// 按顺序执行工具调用计划
    private func executeToolPlan(_ plan: [ToolCallPlan]) async throws -> [ExecutionResult.ToolResult] {
        var results: [ExecutionResult.ToolResult] = []
        
        for step in plan.sorted(by: { $0.order < $1.order }) {
            do {
                let result = try await toolRegistry.executeCanonical(
                    name: step.toolName,
                    args: step.arguments
                )
                
                results.append(ExecutionResult.ToolResult(
                    toolName: step.toolName,
                    success: result.success,
                    result: result.detail,
                    details: [:]
                ))
                
                PCLog.debug("[Orchestrator] 工具 '\(step.toolName)' 执行成功")
            } catch {
                results.append(ExecutionResult.ToolResult(
                    toolName: step.toolName,
                    success: false,
                    result: error.localizedDescription,
                    details: [:]
                ))
                PCLog.warn("[Orchestrator] 工具 '\(step.toolName)' 执行失败: \(error)")
            }
        }
        
        return results
    }
    
    // MARK: - 结果聚合
    
    /// 聚合工具执行结果, 提取 Shortcuts JSON
    private func aggregateResults(_ results: [ExecutionResult.ToolResult]) throws -> ExecutionResult {
        guard !results.isEmpty else {
            return ExecutionResult(
                success: false,
                summary: "没有可执行的工具",
                toolResults: [],
                shortcutsJSON: nil,
                error: "NO_TOOLS"
            )
        }
        
        let allSuccess = results.allSatisfy { $0.success }
        let summary = results.map { $0.result }.joined(separator: "\n\n")
        
        // 提取 Shortcuts JSON
        var shortcutsJSON: String?
        for result in results {
            if result.toolName == "shortcuts-generate" && result.success {
                // JSON 在 detail 中
                if let jsonMatch = try? result.result.matches(of: #"(\{.*\})"#, options: .dotMatchesLineSeparators).first {
                    shortcutsJSON = jsonMatch
                }
            }
        }
        
        return ExecutionResult(
            success: allSuccess,
            summary: summary,
            toolResults: results,
            shortcutsJSON: shortcutsJSON,
            error: allSuccess ? nil : "PARTIAL_FAILURE"
        )
    }
    
    // MARK: - 错误类型
    
    enum OrchestrationError: Error, LocalizedError {
        case noMatchingSkill(String)
        case noToolsAvailable(String)
        case invalidArguments(String, String)
        case executionFailed(String)
        
        var description: String {
            switch self {
            case .noMatchingSkill(let message):
                return "未找到匹配的技能处理您的请求"
            case .noToolsAvailable(let skillId):
                return "技能 '\(skillId)' 没有可用的工具"
            case .invalidArguments(let tool, let reason):
                return "工具 '\(tool)' 参数无效: \(reason)"
            case .executionFailed(let detail):
                return "执行失败: \(detail)"
            }
        }
    }
}

// MARK: - String 扩展: 正则匹配

private extension String {
    func matches(
        of pattern: String,
        options: NSRegularExpression.Options = []
    ) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return []
        }
        let range = NSRange(startIndex..., in: self)
        let matches = regex.matches(in: self, options: [], range: range)
        return matches.compactMap { match in
            let range = match.range
            guard let swiftRange = Range(range, in: self) else { return nil }
            return String(self[swiftRange])
        }
    }
}
