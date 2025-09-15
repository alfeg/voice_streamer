using System.Threading.Channels;
using FFMpegCore;
using FFMpegCore.Pipes;
using Microsoft.Extensions.Options;
using Serilog;

namespace VoiceStreamer;

public class VoiceStreamerClient(IOptions<StreamConfig> config, ChannelReader<VoiceMessageInfo> oggFileChannel, ILogger log) : IDisposable, IBackgroundService
{
    private readonly ILogger _log = log.ForContext("Module", "[VS] ");
    
    private readonly ChannelReader<VoiceMessageInfo> _oggFileChannel =
        oggFileChannel ?? throw new ArgumentNullException(nameof(oggFileChannel));

    private readonly CancellationTokenSource _cts = new();

    public Task Start(CancellationToken cancellationToken = default)
    {
        // Combine caller-provided token with internal CTS for shutdown
        var linkedCts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken, _cts.Token);
        return Task.Run(() => StartContinuousStream(linkedCts.Token), linkedCts.Token);
    }

    private async Task StartContinuousStream(CancellationToken cancellationToken)
    {
        while (!cancellationToken.IsCancellationRequested)
        {
            var stream = new PcmStream(_oggFileChannel, config.Value, log, _cts.Token);
            var audioSource = new StreamPipeSource(stream);

            try
            {
                _log.Information("Старт стриминга в {RtmpServerUrl}{StreamingKey}", config.Value.RtmpServerUrl,
                    config.Value.RtmpStreamKey?.Obfuscate());

                // FFmpeg command: ffmpeg -f s16le -ar 44100 -ac 2 -i pipe:0 -c:a aac -ab 128k -f flv -re rtmp://...
                var arguments = FFMpegArguments
                        .FromPipeInput(audioSource, options => options
                            .WithCustomArgument($"-re -f s16le -ar {PcmStream.SampleRate} -ac {PcmStream.Channels}")
                        )
                        .OutputToUrl(config.Value.GetUrl(), options => options
                            .WithAudioCodec("aac")
                            .WithAudioBitrate(128)
                            .ForceFormat("flv")
                        )
                        .WithLogLevel(FFMpegCore.Enums.FFMpegLogLevel.Info)
                        .NotifyOnOutput(Console.WriteLine)
                    //.NotifyOnError(_log.ForContext("Module", "[VF] ffpmpeg: ").Information)
                    ;

                var taSource = new TaskCompletionSource();
                cancellationToken.Register(() => taSource.SetCanceled(cancellationToken));

                await Task.WhenAny(
                    taSource.Task,
                    arguments.ProcessAsynchronously()
                );

                _log.Information("Остановка стриминга");
            }
            catch (OperationCanceledException oce)
            {
                _log.Error(oce , "Отмена стриминга");
            }
            catch (Exception ex)
            {
                _log.Error(ex, "Ошибка стриминга. Аварийный выход");
            }
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