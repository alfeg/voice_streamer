using System.Diagnostics.Metrics;
using System.Threading.Channels;
using Microsoft.Extensions.Configuration;
using Serilog;
using Serilog.Sinks.TelegramBot;
using Spectre.Console;
using VoiceStreamer;

var config = new ConfigurationBuilder()
    .AddJsonFile("appsettings.json", optional: true)
    .AddCommandLine(args, new Dictionary<string, string>
    {
        ["--code"] = "Telegram:Code"
    })
    .AddEnvironmentVariables()
    .AddUserSecrets(typeof(Program).Assembly)
    .Build();

var streamConfig = config.GetSection("Streamer").Get<StreamConfig>();
var telegramConfig = config.GetSection("Telegram").Get<TelegramConfig>();

var loggerConfiguration = new LoggerConfiguration()
    .WriteTo.Console(outputTemplate: "[{Timestamp:HH:mm:ss} {Level:u3}] {Module}{Message:lj}{NewLine}{Exception}");

if (!string.IsNullOrWhiteSpace(telegramConfig.BotToken) && !string.IsNullOrWhiteSpace(telegramConfig.BotChatId))
{
    loggerConfiguration
        .WriteTo.TelegramBot(telegramConfig.BotToken, telegramConfig.BotChatId);
}

await using var log = loggerConfiguration.CreateLogger();

var voiceChannel = Channel.CreateUnbounded<VoiceMessageInfo>(new UnboundedChannelOptions
    { SingleReader = true, SingleWriter = false });

if (!Directory.Exists("data"))
{
    Directory.CreateDirectory("data");
}

AnsiConsole.Write(new FigletText("Voice Streamer").LeftJustified());

try
{
    using var telegramClient =
        new TelegramClient(telegramConfig, voiceChannel.Writer, log.ForContext("Module", "[TG] "));
    var publisher = new VoiceStreamerClient(streamConfig, voiceChannel.Reader, log.ForContext("Module", "[VS] "));
    var reporter = new AppMetricReporter(log.ForContext("Module", "[VS] "));
    
    log.Information("Ctrl+C для выхода.");

    await Task.WhenAll(
        telegramClient.StartAsync(),
        publisher.StartStreamingAsync(),
        reporter.Start());
}
finally
{
    voiceChannel.Writer.Complete();
}