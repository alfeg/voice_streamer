namespace VoiceStreamer;

public static class StringExtensions
{
    public static string Obfuscate(this string value) =>string.IsNullOrWhiteSpace(value)
        ? string.Empty
        : value.Length > 4
            ? value.Substring(0, 2) + new string('X', value.Length - 4) +
              value.Substring(value.Length - 2)
            : new string('X', value.Length);
}