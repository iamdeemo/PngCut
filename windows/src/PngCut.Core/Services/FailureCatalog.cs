using PngCut.Core.Models;

namespace PngCut.Core.Services;

public static class FailureCatalog
{
    public static string Message(FailureCode code) => code switch
    {
        FailureCode.InputUnreadable => "无法读取输入文件。",
        FailureCode.OutputPolicyInvalid => "输出位置无效。",
        FailureCode.EngineUnavailable => "压缩引擎不可用。",
        FailureCode.EngineFailed => "压缩程序执行失败。",
        FailureCode.OutputInvalid => "压缩程序没有生成有效输出文件。",
        FailureCode.OutputConflict => "输出文件已存在，未覆盖原文件。",
        _ => throw new System.ArgumentOutOfRangeException(nameof(code))
    };
}
