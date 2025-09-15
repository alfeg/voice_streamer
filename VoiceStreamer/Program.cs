using System.Threading.Channels;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;
using Serilog;
using Serilog.Sinks.TelegramBot;
using Spectre.Console;
using VoiceStreamer;

var services = new ServiceCollection();

var config = new ConfigurationBuilder()
    .AddJsonFile("appsettings.json", optional: true)
    .AddCommandLine(args, new Dictionary<string, string>
    {
        ["--code"] = "Telegram:Code"
    })
    .AddEnvironmentVariables()
    .AddUserSecrets(typeof(Program).Assembly)
    .Build();

var loggerConfiguration = new LoggerConfiguration()
    .WriteTo.Console(outputTemplate: "[{Timestamp:HH:mm:ss} {Level:u3}] {Module}{Message:lj}{NewLine}{Exception}");

services.AddOptions<StreamConfig>()
    .Bind(config.GetSection(StreamConfig.Section))
    .ValidateDataAnnotations()
    .ValidateOnStart();

services.AddOptions<TelegramConfig>()
    .Bind(config.GetSection(TelegramConfig.Section))
    .ValidateDataAnnotations()
    .ValidateOnStart();

var voiceChannel = Channel.CreateUnbounded<VoiceMessageInfo>(new UnboundedChannelOptions
    { SingleReader = true, SingleWriter = false });

services.AddSingleton(_ => voiceChannel.Reader);
services.AddSingleton(_ => voiceChannel.Writer);
services.AddSingleton<ILogger>(sp =>
{
    var telegramConfig = sp.GetRequiredService<IOptions<TelegramConfig>>().Value;

    if (!string.IsNullOrWhiteSpace(telegramConfig.BotToken) && !string.IsNullOrWhiteSpace(telegramConfig.BotChatId))
    {
        loggerConfiguration
            .WriteTo.TelegramBot(telegramConfig.BotToken, telegramConfig.BotChatId);
    }

    return loggerConfiguration.CreateLogger();
});

services.AddScoped<IBackgroundService, TelegramClient>();
services.AddScoped<IBackgroundService, VoiceStreamerClient>();
services.AddScoped<IBackgroundService, AppMetricReporter>();

var serviceProvider = services.BuildServiceProvider();

if (!Directory.Exists("data")) Directory.CreateDirectory("data");

AnsiConsole.Write(new FigletText("Voice Streamer").LeftJustified());

try
{
    using var scope = serviceProvider.CreateScope();
    var backgroundServices = scope.ServiceProvider.GetRequiredService<IEnumerable<IBackgroundService>>();
    await Task.WhenAll(backgroundServices.Select(bs => bs.Start(CancellationToken.None)));
}
finally
{
    voiceChannel.Writer.Complete();
}