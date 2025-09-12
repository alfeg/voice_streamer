using FFMpegCore;
using FFMpegCore.Pipes;
using System.Threading.Channels;

public class VoiceStreamerClient
{
    private readonly StreamConfig _config;
    private readonly ChannelReader<string> _oggFileChannel;
    private readonly CancellationTokenSource _cts = new();
    
    public VoiceStreamerClient(StreamConfig config, ChannelReader<string> oggFileChannel)
    {
        _config = config ?? throw new ArgumentNullException(nameof(config));
        _oggFileChannel = oggFileChannel ?? throw new ArgumentNullException(nameof(oggFileChannel));
    }

    public Task StartStreamingAsync(CancellationToken cancellationToken = default)
    {
        // Combine caller-provided token with internal CTS for shutdown
        var linkedCts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken, _cts.Token);
        return Task.Run(() => StartContinuousStream(linkedCts.Token), linkedCts.Token);
    }

    public void StopStreaming()
    {
        _cts.Cancel();
    }

    private async Task StartContinuousStream(CancellationToken cancellationToken)
    {
        var audioSource = new StreamPipeSource(CreatePcmStream());

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

        System.Environment.Exit(1);
    }

    private Stream CreatePcmStream()
    {
        return new PcmStream(_oggFileChannel, _cts.Token);
    }
}