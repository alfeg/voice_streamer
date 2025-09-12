using System.Threading.Channels;
using VoiceStreamer;

var config = new ConfigurationBuilder()
    .AddJsonFile("appsettings.json", optional: true)
    .AddCommandLine(args)
    .AddEnvironmentVariables()
    .AddUserSecrets(typeof(Program).Assembly)
    .Build();

var streamConfig = config.GetSection("Streamer").Get<StreamConfig>();
var telegramConfig = config.GetSection("Telegram").Get<TelegramConfig>();
var voiceChannel = Channel.CreateUnbounded<string>(new UnboundedChannelOptions { SingleReader = true, SingleWriter = false });

if (!Directory.Exists("data"))
{
    Directory.CreateDirectory("data");
}

Console.WriteLine("VoiceStreamer starting...");

try
{
    using var telegramClient = new TelegramClient(telegramConfig, voiceChannel.Writer);
    var publisher = new VoiceStreamerClient(streamConfig, voiceChannel);

    await telegramClient.StartAsync();
    await publisher.StartStreamingAsync();

    Console.WriteLine($"Мониторим {telegramConfig.ChannelToWatch}. Ctrl+C для выхода.");
    Console.ReadLine();
}
finally
{
    voiceChannel.Writer.Complete();
}