using System.Diagnostics;
using System.Threading.Channels;
using FFMpegCore;
using FFMpegCore.Pipes;
using Serilog;
using Spectre.Console;

namespace VoiceStreamer;

internal class PcmStream(ChannelReader<VoiceMessageInfo> oggFileChannel, StreamConfig config, ILogger log, CancellationToken token)
    : Stream
{
    private readonly byte[] _silenceChunk = new byte[ChunkBytes];
    private readonly byte[] _buffer = new byte[ChunkBytes]; // Single chunk buffer
    private int _bufferPosition = 0;
    private int _bufferLength = 0;
    private bool _isDisposed;
    private byte[] _pendingMessagePcm = null;
    private int _messagePosition = 0;
    private long _totalBytesSent = 0; // Tracks the total number of bytes sent to the stream

    // Audio format constants
    public const int SampleRate = 44100;
    public const int Channels = 2;
    public const int BytesPerSample = 2; // s16le
    public const double ChunkDurationSec = 0.4; // 100ms chunks for smooth pacing
    public const int ChunkBytes = (int)(SampleRate * ChunkDurationSec * Channels * BytesPerSample);
    
    static readonly Random rnd = new Random();

    private void FillWithNoise(byte[] buffer)
    {
        for (int i = 0; i < buffer.Length; i += 2)
        {
            // Generate random s16le samples (-32768 to 32767) at low amplitude (±1000 for subtle noise)
            var sample = config.DisableNoise ? (short)0 : (short)(rnd.Next(0, 100));
            buffer[i] = (byte)(sample & 0xFF); // Low byte
            buffer[i + 1] = (byte)((sample >> 8) & 0xFF); // High byte
        }
    }

    public override bool CanRead => true;
    public override bool CanSeek => false;
    public override bool CanWrite => false;
    public override long Length => throw new NotSupportedException();
    public override long Position { get => throw new NotSupportedException(); set => throw new NotSupportedException(); }

    private readonly Stopwatch _stopwatch = Stopwatch.StartNew();
    private VoiceMessageInfo? _messageInfo;

    public override async Task<int> ReadAsync(byte[] buffer, int offset, int count, CancellationToken cancellationToken)
    {
        if (_isDisposed) throw new ObjectDisposedException(nameof(PcmStream));

        int totalBytesRead = 0;
        while (totalBytesRead < count && !token.IsCancellationRequested)
        {
            // If the local buffer has data, copy from it first
            if (_bufferPosition < _bufferLength)
            {
                int bytesToCopy = Math.Min(count - totalBytesRead, _bufferLength - _bufferPosition);
                Array.Copy(_buffer, _bufferPosition, buffer, offset + totalBytesRead, bytesToCopy);

                _bufferPosition += bytesToCopy;
                totalBytesRead += bytesToCopy;
                _totalBytesSent += bytesToCopy; // Update the total sent bytes
                
                // Pacing logic: Wait to align with real-time audio playback.
                double bytesPerSecond = (double)SampleRate * Channels * BytesPerSample;
                double expectedMilliseconds = (_totalBytesSent / bytesPerSecond) * 1000.0;
                double elapsedMilliseconds = _stopwatch.Elapsed.TotalMilliseconds;
                double delayMilliseconds = expectedMilliseconds - elapsedMilliseconds;

                if (delayMilliseconds > 0)
                {
                    // Console.WriteLine($"Pacing delay: {delayMilliseconds:F2}ms. offset: {offset}, count: {count}");
                    try
                    {
                        await Task.Delay((int)delayMilliseconds, cancellationToken);
                    }
                    catch (TaskCanceledException)
                    {
                        return 0; // Return 0 if canceled
                    }
                }

                // If the user's buffer is full, we return and they'll call ReadAsync again.
                if (totalBytesRead == count)
                {
                    return totalBytesRead;
                }
            }

            // If no pending message or finished, check channel
            if (_pendingMessagePcm == null || _messagePosition >= _pendingMessagePcm.Length)
            {
                if (oggFileChannel.TryRead(out var info) && File.Exists(info.FilePath))
                {
                    try
                    {
                        _pendingMessagePcm = await DecodeOggToPcm(info.FilePath);
                        _messageInfo = info;
                        log.Information("{From}> #{MessageId} (-{Delay}) Сообщение готово к отправке", info.Peer, info.Id, info.Delay());
                        _messagePosition = 0;
                        File.Delete(info.FilePath);
                    }
                    catch (Exception ex)
                    {
                        log.Error(ex, "{From}> #{MessageId} (-{Delay}) Непредвиденная ошибка при декодировании сообщения", info.Peer, info.Id, info.Delay());
                        _pendingMessagePcm = null;
                    }
                }
            }

            // If we have message data, serve next chunk
            if (_pendingMessagePcm != null && _messagePosition < _pendingMessagePcm.Length)
            {
                int bytesToCopyFromMessage = Math.Min(ChunkBytes, _pendingMessagePcm.Length - _messagePosition);
                Array.Copy(_pendingMessagePcm, _messagePosition, _buffer, 0, bytesToCopyFromMessage);
                _bufferLength = bytesToCopyFromMessage;
                _bufferPosition = 0;
                _messagePosition += bytesToCopyFromMessage;

                if (_messagePosition >= _pendingMessagePcm.Length)
                {
                    _pendingMessagePcm = null;
                    _messagePosition = 0;
                    log.Information("{From}> #{MessageId} (-{Delay}) Сообщение передано в стрим", _messageInfo?.Peer, _messageInfo?.Id, _messageInfo?.Delay());
                    _messageInfo = null;
                }
            }
            else
            {
                // No file or message data, push silence
                FillWithNoise(_silenceChunk);
                Array.Copy(_silenceChunk, 0, _buffer, 0, ChunkBytes);
                _bufferLength = ChunkBytes;
                _bufferPosition = 0;                
            }
        }

        return totalBytesRead;
    }

    public override void Flush() { }

    public override int Read(byte[] buffer, int offset, int count)
    {
        throw new NotSupportedException();
    }

    public override long Seek(long offset, SeekOrigin origin)
    {
        throw new NotSupportedException();
    }

    public override void SetLength(long value)
    {
        throw new NotSupportedException();
    }

    public override void Write(byte[] buffer, int offset, int count)
    {
        throw new NotSupportedException();
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            _isDisposed = true;
        }
        base.Dispose(disposing);
    }

    private static async Task<byte[]> DecodeOggToPcm(string oggPath)
    {
        using var memoryStream = new MemoryStream();

        await FFMpegArguments
            .FromFileInput(oggPath)
            .OutputToPipe(new StreamPipeSink(memoryStream), options => options
                .WithAudioCodec("pcm_s16le")
                .WithCustomArgument($"-ar {SampleRate} -ac {Channels}")
                .ForceFormat("s16le")
                .DisableChannel(FFMpegCore.Enums.Channel.Video)
            )
            .ProcessAsynchronously();

        return memoryStream.ToArray();
    }
}