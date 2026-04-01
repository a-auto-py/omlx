#!/usr/bin/env bash
# 远程下载 DeepSeek-R1-Distill-Qwen-32B（MLX 4bit），再 rsync 到本机
# 复用 download-model-remote.sh；环境变量与其相同（REMOTE_HOST、REMOTE_USER、MODEL_DIR 等）
# 用法: ./download-deepseek-r1-distill-qwen-32b-4bit-remote.sh

set -e
ROOT="$(cd "$(dirname "$0")" && pwd)"
exec "$ROOT/download-model-remote.sh" "mlx-community/DeepSeek-R1-Distill-Qwen-32B-4bit"
