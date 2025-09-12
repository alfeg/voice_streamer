public record StreamConfig
{
    public string RtmpServerUrl { get; set; }
    public string RtmpStreamKey { get; set; }

    public string GetUrl() => $"{RtmpServerUrl}{RtmpStreamKey}";
}