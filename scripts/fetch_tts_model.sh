#!/usr/bin/env bash
# Downloads a Piper Russian TTS voice for sherpa_onnx and lays it out under
# assets/tts/<voice>/ so it can be bundled into the APK (flutter assets) and
# copied to the app support dir on first launch.
#
# Usage: scripts/fetch_tts_model.sh [voice]
#   voice defaults to: vits-piper-ru_RU-irina-medium
#   alternatives: vits-piper-ru_RU-denis-medium, vits-piper-ru_RU-dmitri-medium,
#                 vits-piper-ru_RU-ruslan-medium
set -euo pipefail

VOICE="${1:-vits-piper-ru_RU-irina-medium}"
BASE="https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models"
ARCHIVE="${VOICE}.tar.bz2"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${ROOT}/assets/tts"

mkdir -p "${DEST}"
cd "${DEST}"

echo "Downloading ${ARCHIVE} ..."
curl -fL --retry 3 -o "${ARCHIVE}" "${BASE}/${ARCHIVE}"

echo "Extracting ..."
tar xjf "${ARCHIVE}"
rm -f "${ARCHIVE}"

echo "Model ready at ${DEST}/${VOICE}"
echo "Expected files: model onnx, tokens.txt, espeak-ng-data/"
ls -1 "${DEST}/${VOICE}" || true

cat <<EOF

Next steps:
  1) Ensure the .onnx inside is named 'model.onnx' (rename if the release ships '<voice>.onnx'):
       mv "${DEST}/${VOICE}/${VOICE}.onnx" "${DEST}/${VOICE}/model.onnx" 2>/dev/null || true
  2) Add to pubspec.yaml under flutter/assets:
       - assets/tts/${VOICE}/
  3) flutter pub get && rebuild.
EOF
