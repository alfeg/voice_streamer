using System.Diagnostics;
using Humanizer;
using Serilog;

namespace VoiceStreamer;

public class AppMetricReporter(ILogger log)
{
    public async Task Start()
    {
        await Task.Yield();
        
        var sw = Stopwatch.StartNew();
        long prevBytesSend = AppMetrics.TotalBytesSend;
        long prevMessages = AppMetrics.TotalMessagesSend;
        
        while (true)
        {
            if (sw.Elapsed.TotalSeconds < 3)
            {
                continue;
            }

            if (AppMetrics.TotalMessagesSend - prevMessages == 0 && sw.Elapsed.TotalSeconds < 30)
            {
                continue;
            }

            log.Information("Messages: {TotalMessages}, Bytes Sent: {TotalBytes} ({Rate})", 
                AppMetrics.TotalMessagesSend, AppMetrics.TotalBytesSend.Bytes().Humanize(),
                (AppMetrics.TotalBytesSend - prevBytesSend).Bytes().Per(sw.Elapsed).Humanize());
            prevBytesSend = AppMetrics.TotalBytesSend;
            prevMessages = AppMetrics.TotalMessagesSend;
                
            sw.Restart();
        }
    }
}