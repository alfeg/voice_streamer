namespace VoiceStreamer;

public static class HelperMethods
{
    public static string Obfuscate(this string value) => string.IsNullOrWhiteSpace(value)
        ? string.Empty
        : value.Length > 4
            ? value.Substring(0, 2) + new string('X', value.Length - 4) +
              value.Substring(value.Length - 2)
            : new string('X', value.Length);

    public static string ToDelayString(this TimeSpan timeSpan)
    {
        if (timeSpan == TimeSpan.Zero)
        {
            return "0ms";
        }

        switch (timeSpan.TotalSeconds)
        {
            // Rule 1: < 1 second, show only milliseconds
            case < 1:
                return $"{(int)timeSpan.TotalMilliseconds}ms";

            // Rule 2: < 3 seconds, show seconds and milliseconds
            case < 3:
            {
                int seconds = (int)timeSpan.TotalSeconds;
                int milliseconds = (int)(timeSpan.TotalMilliseconds % 1000);
                return $"{seconds}s {milliseconds}ms";
            }
            default:
                // Rule 3: >= 3 seconds, show only seconds
                return $"{(int)timeSpan.TotalSeconds}s";
        }
    }
}