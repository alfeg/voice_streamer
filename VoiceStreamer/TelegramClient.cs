using System.Net;
using System.Threading.Channels;
using TL;
using WTelegram;

namespace VoiceStreamer;

public class TelegramClient : IDisposable
{
    private readonly Client _client;
    private readonly UpdateManager _manager;
    private readonly TelegramConfig _config;
    private readonly ChannelWriter<string> _voiceChannel;

    public TelegramClient(TelegramConfig config, ChannelWriter<string> voiceChannel)
    {
        Helpers.Log = (int level, string message) => { };

        _config = config;
        _voiceChannel = voiceChannel;
        _client = new Client(what => what switch
            {
                "api_id" => config.ApiId.ToString(),
                "api_hash" => config.ApiHash,
                "user_id" => config.UserId,
                "phone_number" => config.PhoneNumber,
                "session_pathname" => "data/tg.session",
                "verification_code" or "email_verification_code" or "password" => string.IsNullOrWhiteSpace(config.Code) ? AskCode(what) : config.Code,
                _ => null
            }
        );
        _manager = _client.WithUpdateManager(Client_OnUpdate);
    }

    public string AskCode(string what)
    {
        Console.WriteLine("Handling " + what);
        if (!Environment.UserInteractive || Console.IsInputRedirected)
        {
            Console.WriteLine("Post code to the http://localhost:5151");
            using var listener = new HttpListener();
            try
            {
                listener.Prefixes.Add("http://+:5151/");
                listener.Start();

                var codeProvided = false;

                Console.WriteLine(" curl.exe -d \"xxxxx\" -X POST http://localhost:5151/");

                while (!codeProvided)
                {
                    var context = listener.GetContext();
                    Console.WriteLine("Got request");
                    if (context.Request.HttpMethod != "POST" || context.Request.HasEntityBody == false)
                    {
                        continue;
                    }

                    using (var sr = new StreamReader(context.Request.InputStream))
                    {
                        var body = sr.ReadToEnd();
                        if (int.TryParse(body, out var code))
                        {
                            return body;
                        }
                    }

                    using var sw = new StreamWriter(context.Response.OutputStream);
                    sw.WriteLine("Cannot parse code");
                    context.Response.OutputStream.Flush();

                }
            }
            finally
            {
                listener.Stop();
            }
        }

        return null;
    }

    public async Task StartAsync()
    {
        var myself = await _client.LoginUserIfNeeded();
        Console.WriteLine($"Авторизован как: {myself switch { User u => $"{u.first_name} {u.last_name}", _ => "User" }}");
        Console.WriteLine($"Следим за каналом: {_config.ChannelToWatch}");
    }

    private async Task Client_OnUpdate(Update update)
    {
        switch (update)
        {
            case UpdateNewMessage unm: await HandleMessage(unm.message); break;
            case UpdateEditMessage uem: await HandleMessage(uem.message, true); break;
            case UpdateUserStatus uus: Console.WriteLine($"{User(uus.user_id)} is now {uus.status.GetType().Name[10..]}"); break;
        }
    }

    private string User(long id) => _manager.Users.TryGetValue(id, out var user) ? user.ToString() : $"User {id}";

    readonly List<long> _downloadedFiles = new();

    private async Task HandleMessage(MessageBase messageBase, bool edit = false)
    {
        if (Peer(messageBase.Peer) != _config.ChannelToWatch)
        {
            return;
        }

        // if (edit) Console.Write("(Edit): ");
        switch (messageBase)
        {
            case Message m:
                if (!string.IsNullOrWhiteSpace(m.message))
                {
                    Console.WriteLine($"{(edit ? "(e) " : "    ")}{Peer(m.peer_id)}> {m.message}");
                }

                else if (m.media is MessageMediaDocument { document: Document voiceMessage })
                {
                    if (!_downloadedFiles.Contains(voiceMessage.ID))
                    {
                        _downloadedFiles.Add(voiceMessage.ID);
                        if (_downloadedFiles.Count > 10)
                        {
                            _downloadedFiles.RemoveAt(9);
                        }

                        Console.WriteLine($"Загружаем сообщение {Peer(m.peer_id)} #{voiceMessage.ID}");
                        await DownloadVoiceAsync(voiceMessage, m.ID);
                    }
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

    private async Task DownloadVoiceAsync(Document document, int messageId)
    {
        try
        {
            if (!Directory.Exists("data/downloads"))
            {
                Directory.CreateDirectory("data/downloads");
            }

            var fileName = $"voice_{messageId}_{document.ID}.ogg";
            var filePath = Path.Combine("data","downloads", fileName);
            await using var fileStream = new FileStream(filePath, FileMode.Create, FileAccess.Write);

            try
            {
                await _client.DownloadFileAsync(document, fileStream);
            }
            catch
            {
                await _client.DownloadFileAsync(document, fileStream);
            }
            Console.WriteLine($"Скачано: {fileName}");
            await _voiceChannel.WriteAsync(filePath);
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Ошибка скачивания: {ex.Message}");
        }
    }

    public void Dispose()
    {
        _client?.Dispose();
    }
}
