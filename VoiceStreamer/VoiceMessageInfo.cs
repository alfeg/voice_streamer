namespace VoiceStreamer;

public record VoiceMessageInfo(string FilePath, long Id, string Peer, DateTime Timestamp)
{
    public string Delay()
    {
        var span = DateTime.UtcNow - Timestamp;
        return span.ToDelayString();
    }
}