namespace VoiceStreamer;

public record StreamConfig
{
    public string RtmpServerUrl { get; set; }
    public string RtmpStreamKey { get; set; }

    public bool DisableNoise { get; set; } = false;

    public string GetUrl() => $"{RtmpServerUrl}{RtmpStreamKey}";
}