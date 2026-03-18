#!/usr/bin/env bash
# 从 HuggingFace 下载模型（自动加载 HF_TOKEN，支持断点续传）
# 用法: ./download-model.sh [repo_id]
# 示例: ./download-model.sh mlx-community/Qwen2.5-32B-Instruct-4bit

set -e
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

REPO_ID="${1:-mlx-community/Qwen2.5-32B-Instruct-4bit}"
MODEL_DIR="${MODEL_DIR:-$HOME/models}"

# 加载 omlx.env（HF_TOKEN、HF_ENDPOINT 等）
if [[ -f "$ROOT/omlx.env" ]]; then
  set -a
  source "$ROOT/omlx.env"
  set +a
  [[ -n "$HF_TOKEN" ]] && echo "已加载 HF_TOKEN (前10位: ${HF_TOKEN:0:10}...)"
  [[ -n "$HF_ENDPOINT" ]] && echo "已加载 HF_ENDPOINT: $HF_ENDPOINT"
fi

echo "下载: $REPO_ID (默认缓存，支持断点续传)"
.venv/bin/hf download "$REPO_ID"

# 创建软链接到 oMLX 模型目录
CACHE_NAME="models--${REPO_ID//\//--}"
SNAPSHOT=$(ls -d ~/.cache/huggingface/hub/"$CACHE_NAME"/snapshots/* 2>/dev/null | head -1)
if [[ -n "$SNAPSHOT" && -d "$SNAPSHOT" ]]; then
  LINK_NAME="$MODEL_DIR/$(basename "$REPO_ID")"
  mkdir -p "$MODEL_DIR"
  rm -f "$LINK_NAME"
  ln -sf "$SNAPSHOT" "$LINK_NAME"
  echo "已软链接: $LINK_NAME -> $SNAPSHOT"
else
  echo "未找到快照目录，请手动软链接"
fi
