#!/usr/bin/env bash
#
# iPhone 實機 Demo 啟動器（CR-0026 P0-3）。
#
# 問題：app_config.dart 的 BACKEND_BASE_URL 預設是 http://127.0.0.1:3001，
# iPhone 實機連不到開發機。正確做法是 build 時用 --dart-define 指向「開發機在
# Wi-Fi 上的區網 IP」。這支腳本會自動抓 Mac 的區網 IP 並帶入。
#
# 用法：
#   scripts/run_on_device.sh                 # 自動抓 IP，flutter run 到已連的實機
#   scripts/run_on_device.sh -d <device_id>  # 指定裝置（多裝置時）
#   BACKEND_HOST_IP=192.168.0.23 scripts/run_on_device.sh   # 手動指定 IP
#
# 前置：後端要先用 HOST=0.0.0.0 啟動（.env.example 已預設），手機才連得到：
#   cd backend/stt_proxy && HOST=0.0.0.0 npm start
#
set -euo pipefail

PORT="${BACKEND_PORT:-3001}"

# 1. 決定區網 IP：優先吃環境變數，否則自動偵測（en0 Wi-Fi → en1 fallback）。
ip="${BACKEND_HOST_IP:-}"
if [ -z "$ip" ]; then
  for iface in en0 en1 en2; do
    candidate="$(ipconfig getifaddr "$iface" 2>/dev/null || true)"
    if [ -n "$candidate" ]; then
      ip="$candidate"
      break
    fi
  done
fi

if [ -z "$ip" ]; then
  echo "✗ 找不到區網 IP。請確認已連 Wi-Fi，或手動指定：" >&2
  echo "    BACKEND_HOST_IP=<你的Mac IP> scripts/run_on_device.sh" >&2
  exit 1
fi

BASE_URL="http://${ip}:${PORT}"

echo "──────────────────────────────────────────────"
echo "  後端位址 (BACKEND_BASE_URL) = ${BASE_URL}"
echo "  提醒：後端請用 HOST=0.0.0.0 啟動，手機才連得到："
echo "    cd backend/stt_proxy && HOST=0.0.0.0 npm start"
echo "──────────────────────────────────────────────"

# 2. 帶 dart-define 啟動 Flutter；額外參數（如 -d <device>）原樣傳入。
exec flutter run \
  --dart-define=BACKEND_BASE_URL="${BASE_URL}" \
  "$@"
