# Max Voice Reader — fork of Komet

A stripped, single-purpose Android app built on the [Komet](https://github.com/KometTeam/Komet)
Max-messenger client. It logs into a Max account, lets you pick channels, and for each chosen
channel either **plays the channel's voice messages** aloud or **reads its text messages** aloud with
an **offline, on-device neural TTS** (Russian Piper voice). Purpose: keep listening to channels when
cloud TTS is unreachable (e.g. during a national internet-whitelist window) — nothing but Max's own
servers is required at runtime.

Upstream Komet is reused wholesale for the hard part — the Max protocol (binary MsgPack/LZ4 over TLS to
`api.oneme.ru:443`), phone/OTP auth, chat sync, and OGG/Opus playback. We add a thin "reader" overlay.

## What we added (overlay)

```
lib/reader/channel_config.dart   per-channel WatchMode (off/voice/tts/both) + speed, in SharedPreferences
lib/reader/playback_queue.dart   single sequential just_audio queue (voice URLs + TTS WAVs), speed control
lib/reader/reader_service.dart   subscribes to chats.messageEvents, routes each new message per mode
lib/tts/tts_service.dart         sherpa_onnx OfflineTts (Piper RU) -> WAV
lib/frontend_reader/channels_screen.dart   public-channel list + per-channel mode selector
lib/frontend_reader/player_screen.dart     start/stop, now-playing, queue depth, speed slider
```

Plus minimal edits to `lib/main.dart` (init the overlay; route to `ChannelsScreen`).

## Keeping in sync with upstream Komet (replayable strip)

Upstream is pinned in `UPSTREAM_COMMIT.txt`. The lean tree is derived, not hand-carved:

1. `git fetch upstream && git checkout upstream-mirror && git reset --hard upstream/dev/0.5.0`
2. Re-run the strip: `scripts/strip.sh` (or `scripts/strip.ps1`) — deletes everything listed in
   `scripts/strip.manifest` (frontend, calls, stories, stickers, games, etc.).
3. Re-apply our overlay: our files live in **new, namespaced dirs** (`lib/reader`, `lib/tts`,
   `lib/frontend_reader`) that upstream never touches, so they survive a merge cleanly; the only
   upstream file we edit is `lib/main.dart`, kept as a small patch in `overlay/`.
4. `flutter analyze` and fix any drift.

> The strip script + manifest are authored once the overlay builds against the full tree, so the
> stripped result is verified to still compile.

## TTS model provisioning

`TtsService` loads a Piper Russian voice from `<app-support-dir>/tts/<voiceId>/` containing
`model.onnx`, `tokens.txt`, and `espeak-ng-data/`. Default voice `vits-piper-ru_RU-irina-medium`
(alternatives: denis / dmitri / ruslan). Two ways to get the files onto the device:

- **Bundle (recommended for the offline use-case):** run `scripts/fetch_tts_model.sh <voice>` to
  download+unpack into `assets/tts/<voiceId>/`, add that path to `pubspec.yaml` `flutter/assets`, and
  the app copies it to the support dir on first launch. APK grows ~60 MB but needs no network ever.
- **Sideload:** `adb push` the unpacked model dir to the app's support directory.

Models: https://github.com/k2-fsa/sherpa-onnx/releases (search `vits-piper-ru_RU-*`).

## Build

```
flutter pub get
flutter run                 # debug on a connected Android device
flutter build apk --release --flavor komet
```
Android needs Java 17 (inherited from upstream Komet).

## Status

MVP milestone: reuse Komet login → land on channel picker → per-channel voice/TTS auto-play with a
global speed control. The replayable strip is a follow-up once the overlay is verified building.
