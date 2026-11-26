#!/bin/bash
# 在 iPhone 和 iPad 模拟器上打开 App（连 127.0.0.1:8099 的假播放器），每个页面截一张图
# 用法：screenshots.sh MIAOW.app 输出目录
set -u
APP="$1"; OUT="$2"
mkdir -p "$OUT"
BUNDLE=com.miaow.remote
SERVER=http://127.0.0.1:8099/

# 挑这台机器上有的第一个 iPhone、第一个 iPad
pick() {
  xcrun simctl list devices available -j | python3 -c "
import json, sys
kind = sys.argv[1]
d = json.load(sys.stdin)['devices']
for rt in sorted(d, reverse=True):
    if 'iOS' not in rt: continue
    for x in d[rt]:
        if x['name'].startswith(kind): print(x['udid']); sys.exit()
" "$1"
}

shoot() {   # 设备 名字 启动参数…
  local dev=$1 name=$2; shift 2
  xcrun simctl terminate "$dev" $BUNDLE 2>/dev/null
  xcrun simctl launch "$dev" $BUNDLE "$@" >/dev/null
  sleep 7
  xcrun simctl io "$dev" screenshot "$OUT/$name.png" >/dev/null && echo "截图 $name"
}

for kind in iPhone iPad; do
  dev=$(pick $kind)
  if [ -z "$dev" ]; then echo "没有 $kind 模拟器"; continue; fi
  echo "$kind 模拟器 $dev"
  xcrun simctl boot "$dev" 2>/dev/null
  xcrun simctl bootstatus "$dev" -b >/dev/null
  xcrun simctl ui "$dev" appearance dark
  xcrun simctl status_bar "$dev" override --time 9:41 --batteryState charged --batteryLevel 100 2>/dev/null
  xcrun simctl install "$dev" "$APP"
  k=$(echo $kind | tr 'A-Z' 'a-z')
  shoot "$dev" "${k}_1_连接页"
  shoot "$dev" "${k}_2_专辑墙"   -server $SERVER -shotTab 0
  shoot "$dev" "${k}_3_专辑页"   -server $SERVER -shotTab 0 -shotAlbum 3
  shoot "$dev" "${k}_4_正在播放" -server $SERVER -shotTab 0 -shotNowPlaying YES
  shoot "$dev" "${k}_5_卡带库"   -server $SERVER -shotTab 3
  shoot "$dev" "${k}_6_艺人"     -server $SERVER -shotTab 1
  shoot "$dev" "${k}_7_更多"     -server $SERVER -shotTab 4
  shoot "$dev" "${k}_8_识别"     -server $SERVER -shotTab 0 -shotAlbum 5 -shotIdentify YES
  xcrun simctl shutdown "$dev"
done
ls -la "$OUT"
