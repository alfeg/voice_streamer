# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

DroneHerald (package name `komet`, Android app ID `ru.maxvoice.reader`) is a Flutter app that connects to a messaging backend over a custom packet protocol (MessagePack serialization, LZ4/Zstd compression), subscribes to selected channels, and reads incoming messages aloud with an offline Piper RU TTS voice (sherpa_onnx). Includes a player UI and a fullscreen live message feed. Primary target is Android.

## Commands

```bash
flutter pub get          # install dependencies
flutter analyze          # lint / static analysis
flutter run              # run on connected device (default: komet flavor)

flutter build apk --release --flavor komet --split-per-abi
```

Android builds require **Java 17**.

### TTS model asset

`assets/tts/vits-piper-ru_RU-irina-medium.zip` is not checked in (analyzer warns about it). CI provisions it; to build locally, download `vits-piper-ru_RU-irina-medium.tar.bz2` from `https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/`, rename the `.onnx` inside to `model.onnx`, and zip the folder contents into `assets/tts/vits-piper-ru_RU-irina-medium.zip`.

## Build Flavors

| Flavor | App ID | Notes |
|--------|--------|-------|
| `komet` | `ru.maxvoice.reader` | Default; used for all builds |
| `oneme` | `ru.oneme.app` | Legacy flavor, not built in CI |

## Releases

Version lives in `pubspec.yaml` as `version: X.Y.Z+N` — bump both the semver and the build number together.

1. Bump `version:` in `pubspec.yaml`, commit, push to `main`.
2. Tag and push the tag — this is what triggers the release build:

```bash
git tag vX.Y.Z
git push origin vX.Y.Z
```

Alternatively trigger manually (creates the tag itself):

```bash
gh workflow run release.yml -f version=X.Y.Z
```

`release.yml` builds signed split-per-abi APKs (`--build-name` from the tag, `--build-number` from the CI run number), renames them to `DroneHerald-X.Y.Z-<abi>.apk`, and publishes a GitHub Release with generated notes.

Pushing to `main` without a tag only runs `build-droneherald.yml` (artifact APK, no GitHub Release).

## CI/CD

Two GitHub Actions workflows in `.github/workflows/`:

- `build-droneherald.yml` — push to `main` or manual: builds release APKs, uploads as artifact
- `release.yml` — tag `v*` push or manual dispatch: signed APKs + GitHub Release

Both provision the Piper TTS model zip before building.

## Architecture

```
core/transport/    — raw socket I/O: connection, sender, receiver, dispatcher, proxy
core/protocol/     — Packet struct, opcode map, MessagePack + LZ4/Zstd serialization
core/storage/      — SQLite (sqflite), secure token storage, device identity, spoofing
core/push/         — FCM integration (oneme flavor only)
core/config/       — app config, proxy config, device presets, settings

backend/api.dart   — session lifecycle: connect, handshake, ping, auto-reconnect
backend/modules/   — protocol modules: account, messages, chats, contacts, folders

reader/            — reader core: reader_service (message intake, TTS clipping),
                     channel_config, message_feed, playback_queue
tts/               — tts_service: sherpa_onnx Piper TTS engine

models/            — plain data classes (attachment, chat_info, spoof_profile)

frontend/screens/  — auth screens (login, code confirmation, 2FA, proxy/server settings)
frontend/widgets/  — reusable components (custom_notification, sheets, etc.)
frontend_reader/   — reader UI: channels_screen, player_screen, fullscreen_screen, about
```

Data flow: server → transport → dispatcher → backend module → `reader_service` → `message_feed` / `playback_queue` → TTS + UI.

## Key Conventions

- **No comments in code.** Write self-documenting code instead.
- **Use `showCustomNotification(context, 'text')`** for user-facing notifications — never SnackBars.
- When a fix can be done quickly with a hack or properly with a rewrite, **choose the proper rewrite**.
- Quality over quantity.

## Localization

Two locales: English (`lib/l10n/app_en.arb`) and Russian (`lib/l10n/app_ru.arb`).
Generated code in `lib/l10n/` (produced by `flutter gen-l10n` via `l10n.yaml`).
