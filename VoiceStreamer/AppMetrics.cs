using System.Diagnostics.Metrics;

namespace VoiceStreamer;

internal static class AppMetrics
{
    private static readonly Meter App = new Meter("VoiceStreamer", "1.0.0");

    public static long TotalBytesSend = 0;
    public static long TotalMessagesSend = 0;

    public static readonly ObservableCounter<long> TotalBytesSendCounter =
        App.CreateObservableCounter("Bytes.Send.Total", () => TotalBytesSend, "Bytes");

    public static readonly ObservableCounter<long> TotalMessagesSendCounter =
        App.CreateObservableCounter("Messages.Send.Total", () =>  TotalMessagesSend, "Messages");
}