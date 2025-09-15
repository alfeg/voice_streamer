#!/bin/sh
cd VoiceStreamer
git pull --rebase && docker compose up --build -d && docker compose logs -f