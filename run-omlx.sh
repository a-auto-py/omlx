#!/usr/bin/env bash
# oMLX 后台运行脚本：start | stop | restart | status
# 在 omlx 目录执行: ./run-omlx.sh start

set -e
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

PID_FILE="${PID_FILE:-$ROOT/omlx.pid}"
LOG_DIR="${LOG_DIR:-$HOME/.omlx/logs}"
MODEL_DIR="${MODEL_DIR:-$HOME/models}"

mkdir -p "$LOG_DIR"

start() {
  if [[ -f "$PID_FILE" ]]; then
    pid=$(cat "$PID_FILE")
    if kill -0 "$pid" 2>/dev/null; then
      echo "oMLX 已在运行 (PID $pid)"
      return 0
    fi
    rm -f "$PID_FILE"
  fi

  echo "启动 oMLX (model-dir=$MODEL_DIR, log=$LOG_DIR/server.log)..."
  # 添加 --host 0.0.0.0 以允许局域网访问，添加 --port 指定端口（如有必要）
  nohup .venv/bin/omlx serve --host 0.0.0.0 --port 8000 --model-dir "$MODEL_DIR" >> "$LOG_DIR/server.log" 2>&1 &
  echo $! > "$PID_FILE"
  echo "oMLX 已启动 (PID $(cat "$PID_FILE"))"
  echo "  服务: http://127.0.0.1:8000"
  echo "  管理: http://127.0.0.1:8000/admin"
}

stop() {
  if [[ ! -f "$PID_FILE" ]]; then
    echo "oMLX 未运行"
    return 0
  fi
  pid=$(cat "$PID_FILE")
  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid"
    echo "oMLX 已停止 (PID $pid)"
  else
    echo "oMLX 进程不存在 (PID $pid)"
  fi
  rm -f "$PID_FILE"
}

status() {
  if [[ ! -f "$PID_FILE" ]]; then
    echo "oMLX 未运行"
    return 1
  fi
  pid=$(cat "$PID_FILE")
  if kill -0 "$pid" 2>/dev/null; then
    echo "oMLX 运行中 (PID $pid)"
    echo "  服务: http://127.0.0.1:8000"
    return 0
  else
    echo "oMLX 未运行 (PID 文件存在但进程已退出)"
    rm -f "$PID_FILE"
    return 1
  fi
}

case "${1:-}" in
  start)   start ;;
  stop)    stop ;;
  restart) stop; sleep 2; start ;;
  status)  status ;;
  *)
    echo "用法: $0 {start|stop|restart|status}"
    echo ""
    echo "可选环境变量:"
    echo "  MODEL_DIR  模型目录 (默认: \$HOME/models)"
    echo "  LOG_DIR    日志目录 (默认: \$HOME/.omlx/logs)"
    echo "  PID_FILE   PID 文件 (默认: \$ROOT/omlx.pid)"
    exit 1
    ;;
esac
