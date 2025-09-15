namespace VoiceStreamer;

public interface IBackgroundService
{
    Task Start(CancellationToken cancellationToken);
}