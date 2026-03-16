#!/usr/bin/env bash
# oMLX 源码安装脚本
# 在 omlx 目录执行: ./install-from-source.sh
# 需要: macOS 15+, Python 3.10+, Apple Silicon

set -e
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

# 优先用 Homebrew Python 3.10+
PYTHON=""
for p in /opt/homebrew/opt/python@3.14/bin/python3 \
         /opt/homebrew/opt/python@3.12/bin/python3 \
         /opt/homebrew/opt/python@3.11/bin/python3 \
         /opt/homebrew/opt/python@3.10/bin/python3; do
  if [[ -x "$p" ]]; then
    ver=$("$p" -c 'import sys; print(sys.version_info.major, sys.version_info.minor)' 2>/dev/null)
    if [[ "$ver" =~ ^3\ (1[0-9]|[2-9][0-9]) ]]; then
      PYTHON="$p"
      break
    fi
  fi
done

if [[ -z "$PYTHON" ]]; then
  echo "需要 Python 3.10+，请先安装: brew install python@3.12"
  exit 1
fi

echo "使用 Python: $PYTHON"
"$PYTHON" --version

# 创建 venv 并安装
"$PYTHON" -m venv .venv
.venv/bin/pip install --upgrade pip
.venv/bin/pip install -e .

echo ""
echo "安装完成。启动服务:"
echo "  cd $ROOT && .venv/bin/omlx serve --model-dir ~/models"
echo ""
echo "或激活 venv 后直接: omlx serve --model-dir ~/models"
echo "  source $ROOT/.venv/bin/activate"
