using System.Threading.Channels;
using Humanizer;
using Serilog;
using TL;
using WTelegram;

namespace VoiceStreamer;

public class TelegramClient(TelegramConfig config, ChannelWriter<VoiceMessageInfo> voiceChannel, ILogger log)
    : IDisposable
{
    private Client _client;
    private UpdateManager _manager;

    public async Task StartAsync()
    {
        Helpers.Log = (i, message) => log.Verbose(message);

        log.Information("Запускаем соединение с Telegram. AppId: {AppId}, AppHash: {AppHash}",
            config.ApiId.ToString().Obfuscate(), config.ApiHash.Obfuscate());

        _client = new Client(what => what switch
            {
                "api_id" => config.ApiId.ToString(),
                "api_hash" => config.ApiHash,
                "user_id" => config.UserId,
                "phone_number" => config.PhoneNumber,
                "session_pathname" => "data/tg.session",
                "verification_code" or "email_verification_code" or "password" => HandleVerificationCode(what),
                _ => null
            }
        );

        _manager = _client.WithUpdateManager(Client_OnUpdate);
        var myself = await _client.LoginUserIfNeeded();

        log.Information("Авторизован как: {User}",
            myself switch { User u => $"{u.first_name} {u.last_name}", _ => "User" });
        log.Information("Следим за каналом: {Channel}", config.ChannelToWatch);
    }

    private string? HandleVerificationCode(string what)
    {
        if (!string.IsNullOrWhiteSpace(config.Code))
        {
            return config.Code;
        }

        log.Warning(
            "Был выслан {What}. Установите полученный код в значение переменной Telegram.Code и перезапустите приложение",
            what);
        log.Information("Значение переменной может быть передано как:");
        log.Information(" - переменная окружения: {Sample}", "Telegram__Code=xxx");
        log.Information(" - аргумент коммандной строки: {Sample2} или {Sample3}", "--code xxx", "--Telegram:Code xxx");
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
            //case UpdateUserStatus uus:
            //Console.WriteLine($"{User(uus.user_id)} is now {uus.status.GetType().Name[10..]}"); break;
        }
    }

    private string User(long id) => _manager.Users.TryGetValue(id, out var user) ? user.ToString() : $"User {id}";

    readonly List<long> _downloadedFiles = new();

    private async Task HandleMessage(MessageBase messageBase, bool edit = false)
    {
        if (Peer(messageBase.Peer) != config.ChannelToWatch)
        {
            return;
        }

        switch (messageBase)
        {
            case Message m:
                if (!string.IsNullOrWhiteSpace(m.message))
                {
                    log.Information("{From}> {Message}", Peer(m.peer_id), (edit ? "*" : " ") + m.message);
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
        var chat = _manager.UserOrChat(peer);
        if (chat?.MainUsername != null)
        {
            return "@" + chat.MainUsername;
        }

        return chat?.MainUsername ?? string.Empty;
    }

    private async Task DownloadVoiceAsync(Document document, long messageId, string peer, DateTime timestamp)
    {
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

            log.Information("{From}> #{MessageId} (-{Delay}) Загружаем сообщение", peer, messageId,
                voiceMessageInfo.Delay());

            try
            {
                await _client.DownloadFileAsync(document, fileStream);
            }
            catch
            {
                await _client.DownloadFileAsync(document, fileStream);
            }

            log.Information("{From}> #{MessageId} (-{Delay}) Сообщение загружено  ({Size})", peer, messageId,
                voiceMessageInfo.Delay(), fileStream.Length.Bytes().Humanize());
            await voiceChannel.WriteAsync(voiceMessageInfo);
        }
        catch (Exception ex)
        {
            log.Error(ex, "{From}> #{MessageId} Ошибка скачивания", peer, messageId);
        }
    }

    public void Dispose()
    {
        _client?.Dispose();
    }
}