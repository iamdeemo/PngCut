import Foundation

enum FailureCode: String, CaseIterable, Sendable {
    case inputUnreadable = "input_unreadable"
    case outputPolicyInvalid = "output_policy_invalid"
    case engineUnavailable = "engine_unavailable"
    case engineFailed = "engine_failed"
    case outputInvalid = "output_invalid"
    case outputConflict = "output_conflict"
}

enum FailureCatalog {
    static func message(for code: FailureCode) -> String {
        switch code {
        case .inputUnreadable: "无法读取输入文件。"
        case .outputPolicyInvalid: "输出位置无效。"
        case .engineUnavailable: "压缩引擎不可用。"
        case .engineFailed: "压缩程序执行失败。"
        case .outputInvalid: "压缩程序没有生成有效输出文件。"
        case .outputConflict: "输出文件已存在，未覆盖原文件。"
        }
    }
}
