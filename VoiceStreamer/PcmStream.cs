using FFMpegCore;
using FFMpegCore.Pipes;
using System.Diagnostics;
using System.Threading.Channels;

internal class PcmStream : Stream
{
    private readonly ChannelReader<string> _oggFileChannel;
    private readonly CancellationToken _cancellationToken;
    private readonly byte[] _silenceChunk;
    private readonly byte[] _buffer;
    private int _bufferPosition;
    private int _bufferLength;
    private bool _isDisposed;
    private byte[] _pendingMessagePcm;
    private int _messagePosition;
    private long _totalBytesSent = 0; // Tracks the total number of bytes sent to the stream

    // Audio format constants
    public const int SampleRate = 44100;
    public const int Channels = 2;
    public const int BytesPerSample = 2; // s16le
    public const double ChunkDurationSec = 0.4; // 100ms chunks for smooth pacing
    public const int ChunkBytes = (int)(SampleRate * ChunkDurationSec * Channels * BytesPerSample);
    // public static readonly byte[] SilenceChunk = new byte[ChunkBytes]; // All zeros for silence
    public static readonly byte[] SilenceChunk;

    public PcmStream(ChannelReader<string> oggFileChannel, CancellationToken cancellationToken)
    {
        _oggFileChannel = oggFileChannel;
        _cancellationToken = cancellationToken;
        _silenceChunk = SilenceChunk;
        _buffer = new byte[ChunkBytes]; // Single chunk buffer
        _bufferPosition = 0;
        _bufferLength = 0;
        _pendingMessagePcm = null;
        _messagePosition = 0;
    }

    static PcmStream()
    {
        // Initialize SilenceChunk with low-amplitude white noise for debugging
        SilenceChunk = new byte[ChunkBytes];
        var random = new Random();
        for (int i = 0; i < SilenceChunk.Length; i += 2)
        {
            // Generate random s16le samples (-32768 to 32767) at low amplitude (±1000 for subtle noise)
            short sample = (short)(random.Next(-1000, 1001));
            SilenceChunk[i] = (byte)(sample & 0xFF); // Low byte
            SilenceChunk[i + 1] = (byte)((sample >> 8) & 0xFF); // High byte
        }
    }

    static readonly Random rnd = new Random();

    private static void FillWithNoise(byte[] buffer)
    {
        for (int i = 0; i < buffer.Length; i += 2)
        {
            // Generate random s16le samples (-32768 to 32767) at low amplitude (±1000 for subtle noise)
            short sample = (short)(rnd.Next(0, 100));
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

    public override async Task<int> ReadAsync(byte[] buffer, int offset, int count, CancellationToken cancellationToken)
    {
        if (_isDisposed) throw new ObjectDisposedException(nameof(PcmStream));

        int totalBytesRead = 0;
        while (totalBytesRead < count && !_cancellationToken.IsCancellationRequested)
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
                if (_oggFileChannel.TryRead(out var oggPath) && File.Exists(oggPath))
                {
                    try
                    {
                        _pendingMessagePcm = await DecodeOggToPcm(oggPath);
                        Console.WriteLine($"[{Path.GetFileName(oggPath)}] Передаем в стрим");
                        _messagePosition = 0;
                        File.Delete(oggPath);
                    }
                    catch (Exception ex)
                    {
                        Console.WriteLine($"Error processing {oggPath}: {ex.Message}");
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
                    Console.WriteLine("Сообщение передано в стрим");
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