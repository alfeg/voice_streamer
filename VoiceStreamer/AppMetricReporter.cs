using System.Diagnostics;
using Humanizer;
using Serilog;

namespace VoiceStreamer;

public class AppMetricReporter(ILogger log) : IBackgroundService
{
    private readonly ILogger _log = log.ForContext("Module", "[VS] ");
    
    public async Task Start(CancellationToken cancellationToken)
    {
        await Task.Yield();
        
        var sw = Stopwatch.StartNew();
        long prevBytesSend = AppMetrics.TotalBytesSend;
        long prevMessages = AppMetrics.TotalMessagesSend;

        int delay = 10;
        int NextDelay() => (int)Math.Min(delay * Math.E, 60 * 60);
        
        while (cancellationToken.IsCancellationRequested == false)
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

            _log.Information("Messages: {TotalMessages}, Bytes Sent: {TotalBytes} ({Rate})", 
                AppMetrics.TotalMessagesSend, AppMetrics.TotalBytesSend.Bytes().Humanize(),
                (AppMetrics.TotalBytesSend - prevBytesSend).Bytes().Per(sw.Elapsed).Humanize());
            prevBytesSend = AppMetrics.TotalBytesSend;
            prevMessages = AppMetrics.TotalMessagesSend;
                
            sw.Restart();
        }
    }
}