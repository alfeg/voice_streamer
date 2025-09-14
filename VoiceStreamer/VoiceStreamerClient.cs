using System.Threading.Channels;
using FFMpegCore;
using FFMpegCore.Pipes;
using Serilog;

namespace VoiceStreamer;

public class VoiceStreamerClient(StreamConfig config, ChannelReader<VoiceMessageInfo> oggFileChannel, ILogger log) : IDisposable
{
    private readonly StreamConfig _config = config ?? throw new ArgumentNullException(nameof(config));

    private readonly ChannelReader<VoiceMessageInfo> _oggFileChannel =
        oggFileChannel ?? throw new ArgumentNullException(nameof(oggFileChannel));

    private readonly CancellationTokenSource _cts = new();

    public Task StartStreamingAsync(CancellationToken cancellationToken = default)
    {
        // Combine caller-provided token with internal CTS for shutdown
        var linkedCts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken, _cts.Token);
        return Task.Run(() => StartContinuousStream(linkedCts.Token), linkedCts.Token);
    }

    private async Task StartContinuousStream(CancellationToken cancellationToken)
    {
        var stream = new PcmStream(_oggFileChannel, config, log, _cts.Token);
        var audioSource = new StreamPipeSource(stream);

        try
        {
            log.Information("Старт стриминга в {RtmpServerUrl}{StreamingKey}", _config.RtmpServerUrl, _config.RtmpStreamKey.Obfuscate());
            
            // FFmpeg command: ffmpeg -f s16le -ar 44100 -ac 2 -i pipe:0 -c:a aac -ab 128k -f flv -re rtmp://...
            var arguments = FFMpegArguments
                    .FromPipeInput(audioSource, options => options
                        .WithCustomArgument($"-re -f s16le -ar {PcmStream.SampleRate} -ac {PcmStream.Channels}")
                    )
                    .OutputToUrl(_config.GetUrl(), options => options
                            .WithAudioCodec("aac")
                            .WithAudioBitrate(128)
                            .ForceFormat("flv")
                        //  .WithCustomArgument("-re") // Ensure real-time pacing
                    )
                    .WithLogLevel(FFMpegCore.Enums.FFMpegLogLevel.Info)
                    .NotifyOnOutput(Console.WriteLine)
                  //.NotifyOnError(log.ForContext("Module", "[VF] ffpmpeg: ").Information)
                ;

            var taSource = new TaskCompletionSource();
            cancellationToken.Register(() => taSource.SetCanceled(cancellationToken));
            
            await Task.WhenAny(
                taSource.Task,
                arguments.ProcessAsynchronously()
            );
            
            log.Information("Остановка стриминга");
        }
        catch (OperationCanceledException)
        {
            log.Information("Отмена стриминга");
        }
        catch (Exception ex)
        {
            log.Error(ex, "Ошибка стриминга. Аварийный выход");
            Environment.Exit(1);
        }
    }

    public void StopStreaming()
    {
        _cts.Cancel();
    }

    public void Dispose()
    {
        StopStreaming();
    }
}