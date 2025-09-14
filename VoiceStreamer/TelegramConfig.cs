namespace VoiceStreamer;

public record TelegramConfig
{
    public int ApiId { get; set; }
    public string ApiHash { get; set; }
    public string Code { get; set; }
    public string ChannelToWatch { get; set; }
    public string UserId { get; set; }
    public string PhoneNumber { get; set; }
}