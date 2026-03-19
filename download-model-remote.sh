#!/usr/bin/env bash
# 在远程服务器下载模型，再 rsync 同步到本机
# 用法: ./download-model-remote.sh [repo_id]
# 示例: ./download-model-remote.sh mlx-community/Qwen2.5-VL-7B-Instruct-4bit
#
# 环境变量:
#   REMOTE_HOST    远程主机 (默认: 10.88.88.13)
#   REMOTE_USER    远程用户 (默认: root)
#   REMOTE_MODELS  远程模型目录 (默认: /root/models)
#   MODEL_DIR      本机模型目录 (默认: $HOME/models)

set -e
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

REPO_ID="${1:-mlx-community/Qwen2.5-VL-7B-Instruct-4bit}"
REMOTE_HOST="${REMOTE_HOST:-10.88.88.13}"
REMOTE_USER="${REMOTE_USER:-root}"
REMOTE_MODELS="${REMOTE_MODELS:-/root/models}"
MODEL_DIR="${MODEL_DIR:-$HOME/models}"
REMOTE="$REMOTE_USER@$REMOTE_HOST"

# 模型在 HF 缓存中的目录名
CACHE_NAME="models--${REPO_ID//\//--}"
LOCAL_NAME="$(basename "$REPO_ID")"

echo "==> 远程下载 + 同步"
echo "    模型: $REPO_ID"
echo "    远程: $REMOTE"
echo "    本机: $MODEL_DIR/$LOCAL_NAME"
echo ""

# 1. 同步 omlx.env 到远程（含 HF_TOKEN）
if [[ -f "$ROOT/omlx.env" ]]; then
  echo "==> 同步 omlx.env 到远程..."
  scp "$ROOT/omlx.env" "$REMOTE:/tmp/omlx-download.env" || {
    echo "错误: 无法 scp omlx.env，请确保 SSH 免密已配置"
    exit 1
  }
  ENV_CMD="set -a && source /tmp/omlx-download.env && set +a &&"
else
  echo "警告: 未找到 omlx.env，远程下载可能限速。可复制 omlx.env.example 为 omlx.env 并填入 HF_TOKEN"
  ENV_CMD=""
fi

# 2. 在远程执行下载
echo "==> 在远程执行 hf download（支持断点续传）..."
ssh "$REMOTE" bash -s << REMOTE_SCRIPT
  $ENV_CMD
  export PATH="/usr/local/bin:/usr/bin:\$PATH"
  if command -v hf &>/dev/null; then
    hf download $REPO_ID
  elif command -v huggingface-cli &>/dev/null; then
    huggingface-cli download $REPO_ID
  else
    # 远程为 Debian/Ubuntu 时 PEP 668 禁止 pip 装系统包，优先用 venv
    VENV_DIR="/tmp/hf-download-venv"
    if [[ ! -d "\$VENV_DIR" ]]; then
      if ! python3 -m venv "\$VENV_DIR" 2>/dev/null; then
        pip3 install --user -q huggingface_hub || { echo "错误: 请先在远程执行 apt install python3-venv"; exit 1; }
      else
        "\$VENV_DIR/bin/pip" install -q huggingface_hub
      fi
    fi
    if [[ -d "\$VENV_DIR" ]]; then
      "\$VENV_DIR/bin/pip" install -q huggingface_hub 2>/dev/null || true
      "\$VENV_DIR/bin/python" -c "
from huggingface_hub import snapshot_download
snapshot_download('$REPO_ID')
"
    else
      python3 -c "
from huggingface_hub import snapshot_download
snapshot_download('$REPO_ID')
"
    fi
  fi
REMOTE_SCRIPT

# 3. 定位远程快照目录
echo "==> 查找远程快照目录..."
REMOTE_SNAPSHOT=$(ssh "$REMOTE" "ls -d ~/.cache/huggingface/hub/$CACHE_NAME/snapshots/* 2>/dev/null | head -1")
if [[ -z "$REMOTE_SNAPSHOT" ]]; then
  REMOTE_SNAPSHOT=$(ssh "$REMOTE" "ls -d /root/.cache/huggingface/hub/$CACHE_NAME/snapshots/* 2>/dev/null | head -1")
fi
if [[ -z "$REMOTE_SNAPSHOT" ]]; then
  echo "错误: 远程未找到 $CACHE_NAME 快照目录"
  exit 1
fi
echo "    远程路径: $REMOTE_SNAPSHOT"

# 4. rsync 拉回本机（-L 跟随符号链接，复制实际文件而非断链）
echo "==> rsync 同步到本机..."
mkdir -p "$MODEL_DIR"
rsync -avzL --progress "$REMOTE:$REMOTE_SNAPSHOT/" "$MODEL_DIR/$LOCAL_NAME/"

echo ""
echo "==> 完成: $MODEL_DIR/$LOCAL_NAME"
echo "    启动 oMLX: ./run-omlx.sh start"
echo "    配置 OpenClaw 使用: omlx/$LOCAL_NAME"
