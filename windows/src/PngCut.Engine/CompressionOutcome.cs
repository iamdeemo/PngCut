namespace PngCut.Engine;

public enum CompressionOutcome
{
    Compressed,
    NoChange
}

public sealed class CompressionException : System.Exception
{
    public CompressionException(string message)
        : base(message)
    {
    }
}
