using System.Threading.Channels;
using Humanizer;
using Microsoft.Extensions.Options;
using Serilog;
using TL;
using WTelegram;

namespace VoiceStreamer;

public class TelegramClient(IOptions<TelegramConfig> options, 
    ChannelWriter<VoiceMessageInfo> voiceChannel, ILogger log)
    : IDisposable,IBackgroundService
{
    private readonly ILogger _log = log.ForContext("Module", "[TG] ");
    private readonly TelegramConfig _config = options.Value;
    
    private Client? _client;
    private UpdateManager? _manager;

    public async Task Start(CancellationToken cancellationToken)
    {
        if (_config.ApiHash == null || _config.ApiId == null)
        {
            _log.Fatal("Telegram__ApiHash и Telegram__Api обязательные параметры");
            Environment.Exit(1);
        }
        
        // ReSharper disable once TemplateIsNotCompileTimeConstantProblem
        Helpers.Log = (_, message) => _log.Verbose(message);

        _log.Information("Запускаем соединение с Telegram. AppId: {AppId}, AppHash: {AppHash}",
            _config.ApiId.ToString()!.Obfuscate(), _config.ApiHash.Obfuscate());

        _client = new Client(what => what switch
            {
                "api_id" => _config.ApiId.ToString(),
                "api_hash" => _config.ApiHash,
                "user_id" => _config.UserId,
                "phone_number" => _config.PhoneNumber,
                "session_pathname" => "data/tg.session",
                "verification_code" or "email_verification_code" or "password" => HandleVerificationCode(what),
                _ => null
            }
        );

        _manager = _client.WithUpdateManager(Client_OnUpdate);
        var myself = await _client.LoginUserIfNeeded();

        _log.Information("Авторизован как: {User}",
            myself switch
            {
                { } u => $"{u.first_name} {u.last_name}",
                _ => "User"
            });
        _log.Information("Следим за каналом: {Channel}", _config.ChannelToWatch);
    }

    private string? HandleVerificationCode(string what)
    {
        if (!string.IsNullOrWhiteSpace(_config.Code))
        {
            return _config.Code;
        }

        _log.Warning(
            "Был выслан {What}. Установите полученный код в значение переменной Telegram.Code и перезапустите приложение",
            what);
        _log.Information("Значение переменной может быть передано как:");
        _log.Information(" - переменная окружения: {Sample}", "Telegram__Code=xxx");
        _log.Information(" - аргумент коммандной строки: {Sample2} или {Sample3}", "--code xxx", "--Telegram:Code xxx");
        Console.ReadLine();
        Environment.Exit(0);
        return null;
    }

    private async Task Client_OnUpdate(Update update)
    {
        switch (update)
        {
            case UpdateNewMessage unm: await HandleMessage(unm.message); break;
            case UpdateEditMessage uem: await HandleMessage(uem.message, true); break;
        }
    }

    readonly List<long> _downloadedFiles = new();

    private async Task HandleMessage(MessageBase messageBase, bool edit = false)
    {
        if (Peer(messageBase.Peer) != _config.ChannelToWatch)
        {
            return;
        }

        switch (messageBase)
        {
            case Message m:
                if (!string.IsNullOrWhiteSpace(m.message))
                {
                    _log.Information("{From}> {Message}", Peer(m.peer_id), (edit ? "*" : " ") + m.message);
                }

                else if (m.media is MessageMediaDocument { document: Document voiceMessage })
                {
                    if (_downloadedFiles.Contains(voiceMessage.ID) || edit) break;
                    _downloadedFiles.Add(voiceMessage.ID);
                    if (_downloadedFiles.Count > 20) _downloadedFiles.RemoveAt(9);
                    await DownloadVoiceAsync(voiceMessage, voiceMessage.ID, Peer(m.peer_id), m.Date);
                }

                break;
        }
    }

    private string Peer(Peer peer)
    {
        var chat = _manager?.UserOrChat(peer);
        if (chat?.MainUsername != null)
        {
            return "@" + chat.MainUsername;
        }

        return chat?.MainUsername ?? string.Empty;
    }

    private async Task DownloadVoiceAsync(Document document, long messageId, string peer, DateTime timestamp)
    {
        if (_client == null)
        {
            throw new ApplicationException("Telegram клиент не инициализорован");
        }
        
        try
        {
            if (!Directory.Exists("data/downloads"))
            {
                Directory.CreateDirectory("data/downloads");
            }

            var fileName = $"voice_{messageId}.ogg";
            var filePath = Path.Combine("data", "downloads", fileName);
            var voiceMessageInfo = new VoiceMessageInfo(filePath, messageId, peer, timestamp);

            await using var fileStream = new FileStream(filePath, FileMode.Create, FileAccess.Write);

            _log.Information("{From}> #{MessageId} (-{Delay}) Загружаем сообщение", peer, messageId,
                voiceMessageInfo.Delay());

            try
            {
                await _client.DownloadFileAsync(document, fileStream);
            }
            catch
            {
                await _client.DownloadFileAsync(document, fileStream);
            }

            _log.Information("{From}> #{MessageId} (-{Delay}) Сообщение загружено  ({Size})", peer, messageId,
                voiceMessageInfo.Delay(), fileStream.Length.Bytes().Humanize());
            await voiceChannel.WriteAsync(voiceMessageInfo);
        }
        catch (Exception ex)
        {
            _log.Error(ex, "{From}> #{MessageId} Ошибка скачивания", peer, messageId);
        }
    }

    public void Dispose()
    {
        _client?.Dispose();
    }
}