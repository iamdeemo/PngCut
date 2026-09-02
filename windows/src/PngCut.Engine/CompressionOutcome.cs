using PngCut.Core.Models;

namespace PngCut.Engine;

public enum CompressionOutcome
{
    Compressed,
    NoChange
}

public sealed class CompressionException : System.Exception
{
    public CompressionException(FailureCode code, string technicalMessage)
        : base(technicalMessage)
    {
        Code = code;
    }

    public FailureCode Code { get; }
}
