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

        int delay = 10;
        int NextDelay() => (int)Math.Min(delay * Math.E, 60 * 60);
        
        while (true)
        {
            if (sw.Elapsed.TotalSeconds < 3)
            {
                await Task.Delay(TimeSpan.FromSeconds(1));
                continue;
            }

            if (AppMetrics.TotalMessagesSend - prevMessages == 0 )
            {
                if (sw.Elapsed.TotalSeconds < delay)
                {
                    await Task.Delay(TimeSpan.FromSeconds(1));
                    continue;
                }

                delay = NextDelay();
            }
            else
            {
                delay = 60;
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