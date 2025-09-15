using System.ComponentModel.DataAnnotations;

namespace VoiceStreamer;

public record TelegramConfig
{
    public const string Section = "Telegram";
    
    [Required(ErrorMessage = "AppId обязательный аргумент")]
    public int? ApiId { get; set; }
    
    [Required(ErrorMessage = "ApiHash обязательный аргумент")]
    public string? ApiHash { get; set; }
    public string? Code { get; set; }
    
    [Required(ErrorMessage = "ChannelsToWatch обязательный аргумент")]
    public string? ChannelsToWatch { get; set; }
    public string? UserId { get; set; }
    
    [Required(ErrorMessage = "AppId обязательный аргумент")]
    public string? PhoneNumber { get; set; }
    
    public string? BotToken { get; set; }
    
    public string? BotChatId { get; set; }
}