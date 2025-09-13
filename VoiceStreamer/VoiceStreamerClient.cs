using FFMpegCore;
using FFMpegCore.Pipes;
using System.Threading.Channels;

public class VoiceStreamerClient(StreamConfig config, ChannelReader<string> oggFileChannel)
{
    private readonly StreamConfig _config = config ?? throw new ArgumentNullException(nameof(config));
    private readonly ChannelReader<string> _oggFileChannel = oggFileChannel ?? throw new ArgumentNullException(nameof(oggFileChannel));
    private readonly CancellationTokenSource _cts = new();

    public Task StartStreamingAsync(CancellationToken cancellationToken = default)
    {
        // Combine caller-provided token with internal CTS for shutdown
        var linkedCts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken, _cts.Token);
        return Task.Run(() => StartContinuousStream(), linkedCts.Token);
    }

    public void StopStreaming()
    {
        _cts.Cancel();
    }

    private async Task StartContinuousStream()
    {
        var stream = new PcmStream(_oggFileChannel, config, _cts.Token);
        var audioSource = new StreamPipeSource(stream);

        try
        {
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
               // .NotifyOnError(Console.WriteLine)
                ;

            await arguments.ProcessAsynchronously();
            Console.WriteLine("Streaming stopped gracefully.");
        }
        catch (OperationCanceledException)
        {
            Console.WriteLine("Streaming cancelled.");
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Streaming error: {ex.Message}");
        }

        Environment.Exit(1);
    }
}