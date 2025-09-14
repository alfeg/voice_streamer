using System.Diagnostics.Metrics;

namespace VoiceStreamer;

internal static class AppMetrics
{
    public static Meter App = new Meter("VoiceStreamer", "1.0.0");

    public static long TotalBytesSend = 0;
    public static long TotalMessagesSend = 0;

    public static ObservableCounter<long> TotalBytesSendCounter =
        App.CreateObservableCounter<long>("Bytes.Send.Total", () => TotalBytesSend, "Bytes");

    public static ObservableCounter<long> TotalMessagesSendCounter =
        App.CreateObservableCounter<long>("Messages.Send.Total", () =>  TotalMessagesSend, "Messages");
}