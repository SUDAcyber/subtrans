#!/usr/bin/env bash
set -euo pipefail

ROOT="${TYPHOON_ROOT:-$HOME/Library/Application Support/SUDA字幕翻译助手/typhoon}"
TOOLS="$ROOT/tools"
VENV="$ROOT/venv"
UV="$TOOLS/uv"

status() {
  echo "STATUS $1"
}

mkdir -p "$TOOLS"

if [[ ! -x "$UV" ]]; then
  status "正在下载 Typhoon 安装器"
  case "$(uname -m)" in
    arm64) UV_ARCHIVE="uv-aarch64-apple-darwin.tar.gz" ;;
    x86_64) UV_ARCHIVE="uv-x86_64-apple-darwin.tar.gz" ;;
    *) echo "不支持的 Mac 架构: $(uname -m)" >&2; exit 2 ;;
  esac
  TMP_DIR="$(mktemp -d)"
  trap 'rm -rf "$TMP_DIR"' EXIT
  curl --fail --location --retry 3 \
    "https://github.com/astral-sh/uv/releases/latest/download/$UV_ARCHIVE" \
    --output "$TMP_DIR/uv.tar.gz"
  tar -xzf "$TMP_DIR/uv.tar.gz" -C "$TMP_DIR"
  UV_SOURCE="$(find "$TMP_DIR" -type f -name uv -perm +111 | head -1)"
  [[ -n "$UV_SOURCE" ]] || { echo "无法解压 uv" >&2; exit 3; }
  cp "$UV_SOURCE" "$UV"
  chmod +x "$UV"
fi

status "正在准备 Python 3.11"
"$UV" python install 3.11
"$UV" venv --python 3.11 --clear "$VENV"

status "正在安装 Typhoon ASR 依赖 约 2GB"
"$UV" pip install --python "$VENV/bin/python3" \
  "typhoon-asr==0.1.1" "librosa==0.11.0" "soundfile==0.14.0"

status "正在验证 Typhoon ASR"
"$VENV/bin/python3" -c 'import librosa, soundfile, nemo.collections.asr'

status "Typhoon ASR 已安装"
