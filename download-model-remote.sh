#!/usr/bin/env bash
# 在远程服务器下载模型，再 rsync 同步到本机
# 用法: ./download-model-remote.sh [repo_id]
# 示例: ./download-model-remote.sh mlx-community/Qwen2.5-VL-7B-Instruct-4bit
#
# 环境变量:
#   REMOTE_HOST    远程主机 (默认: 10.88.88.13)
#   REMOTE_USER    远程用户 (默认: root)
#   REMOTE_MODELS  远程模型目录 (默认: /root/models)
#   MODEL_DIR          本机模型目录 (默认: $HOME/models)
#   RSYNC_EXTRA_FLAGS  追加传给 rsync 的参数（可选）
#
# HuggingFace 认证（按顺序找第一个存在的文件）:
#   1) $OMLX_ENV_PATH（显式指定）
#   2) 脚本目录下 omlx.env
#   3) $HOME/.config/omlx/omlx.env
#   若均无，可用本机 export 的 HF_TOKEN（及可选 HF_ENDPOINT）生成临时文件 scp 到远程

set -e
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

OMLX_ENV_RESOLVED=""
if [[ -n "${OMLX_ENV_PATH:-}" && -f "${OMLX_ENV_PATH}" ]]; then
  OMLX_ENV_RESOLVED="$OMLX_ENV_PATH"
elif [[ -f "$ROOT/omlx.env" ]]; then
  OMLX_ENV_RESOLVED="$ROOT/omlx.env"
elif [[ -f "${HOME}/.config/omlx/omlx.env" ]]; then
  OMLX_ENV_RESOLVED="${HOME}/.config/omlx/omlx.env"
fi

REPO_ID="${1:-mlx-community/Qwen2.5-VL-7B-Instruct-4bit}"
REMOTE_HOST="${REMOTE_HOST:-10.88.88.13}"
REMOTE_USER="${REMOTE_USER:-root}"
REMOTE_MODELS="${REMOTE_MODELS:-/root/models}"
MODEL_DIR="${MODEL_DIR:-$HOME/models}"
REMOTE="$REMOTE_USER@$REMOTE_HOST"
RSYNC_EXTRA_FLAGS="${RSYNC_EXTRA_FLAGS:-}"

# 模型在 HF 缓存中的目录名
CACHE_NAME="models--${REPO_ID//\//--}"
LOCAL_NAME="$(basename "$REPO_ID")"

echo "==> 远程下载 + 同步"
echo "    模型: $REPO_ID"
echo "    远程: $REMOTE"
echo "    本机: $MODEL_DIR/$LOCAL_NAME"
echo ""

# 1. 同步 HF 凭据到远程（omlx.env 路径见上方；否则用本机 HF_TOKEN）
if [[ -n "$OMLX_ENV_RESOLVED" ]]; then
  echo "==> 同步凭据到远程: $OMLX_ENV_RESOLVED"
  scp "$OMLX_ENV_RESOLVED" "$REMOTE:/tmp/omlx-download.env" || {
    echo "错误: 无法 scp 凭据文件，请确保 SSH 免密已配置"
    exit 1
  }
elif [[ -n "${HF_TOKEN:-}" ]]; then
  echo "==> 使用本机环境变量 HF_TOKEN 生成临时凭据并同步到远程..."
  ENV_LOCAL_FILE=$(mktemp)
  {
    printf 'HF_TOKEN=%q\n' "$HF_TOKEN"
    [[ -n "${HF_ENDPOINT:-}" ]] && printf 'HF_ENDPOINT=%q\n' "$HF_ENDPOINT"
  } >"$ENV_LOCAL_FILE"
  scp "$ENV_LOCAL_FILE" "$REMOTE:/tmp/omlx-download.env" || {
    rm -f "$ENV_LOCAL_FILE"
    echo "错误: 无法 scp 凭据到远程，请检查 SSH 免密"
    exit 1
  }
  rm -f "$ENV_LOCAL_FILE"
else
  echo "警告: 未找到 omlx.env（可用 OMLX_ENV_PATH 指定）且未设置 HF_TOKEN，远程下载可能限速。"
  echo "      可: cp omlx.env.example omlx.env 并填入 Token，或 export HF_TOKEN=... 后再运行"
  ssh "$REMOTE" "rm -f /tmp/omlx-download.env" 2>/dev/null || true
fi

# 2. 在远程执行下载（带引号 heredoc，避免本机误展开导致「download: command not found」等）
echo "==> 在远程执行 hf download（支持断点续传）..."
# shellcheck disable=SC2029
ssh "$REMOTE" "export REPO_ID=$(printf %q "$REPO_ID"); bash -s" <<'REMOTE_SCRIPT'
set -e
[[ -f /tmp/omlx-download.env ]] && set -a && source /tmp/omlx-download.env && set +a
export PATH="/usr/local/bin:/usr/bin:$PATH"
if command -v hf &>/dev/null; then
  hf download "$REPO_ID"
elif command -v huggingface-cli &>/dev/null; then
  huggingface-cli download "$REPO_ID"
else
  VENV_DIR="/tmp/hf-download-venv"
  if [[ ! -d "$VENV_DIR" ]]; then
    if ! python3 -m venv "$VENV_DIR" 2>/dev/null; then
      pip3 install --user -q huggingface_hub || { echo "错误: 请先在远程执行 apt install python3-venv"; exit 1; }
    else
      "$VENV_DIR/bin/pip" install -q huggingface_hub
    fi
  fi
  if [[ -d "$VENV_DIR" ]]; then
    "$VENV_DIR/bin/pip" install -q huggingface_hub 2>/dev/null || true
    "$VENV_DIR/bin/python" -c 'import os; from huggingface_hub import snapshot_download; snapshot_download(os.environ["REPO_ID"])'
  else
    python3 -c 'import os; from huggingface_hub import snapshot_download; snapshot_download(os.environ["REPO_ID"])'
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

# 4. rsync 拉回本机（不用 -z：大权重多为不可压缩二进制，压缩易触发 deflate/协议错误 code 12）
echo "==> rsync 同步到本机..."
mkdir -p "$MODEL_DIR"
# shellcheck disable=SC2086
rsync -avL --partial --progress $RSYNC_EXTRA_FLAGS "$REMOTE:$REMOTE_SNAPSHOT/" "$MODEL_DIR/$LOCAL_NAME/"

echo ""
echo "==> 完成: $MODEL_DIR/$LOCAL_NAME"
echo "    启动 oMLX: ./run-omlx.sh start"
echo "    配置 OpenClaw 使用: omlx/$LOCAL_NAME"
