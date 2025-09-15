using System.ComponentModel.DataAnnotations;

namespace VoiceStreamer;

public record StreamConfig
{
    public const string Section = "Streamer";
    
    [Required(ErrorMessage = "RtmpServerUrl обязательный аргумент для трансляции")]
    public string? RtmpServerUrl { get; set; }
    public string? RtmpStreamKey { get; set; }

    public bool DisableNoise { get; set; } = false;

    public string GetUrl() => $"{RtmpServerUrl}{RtmpStreamKey}";
}