#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ICON="$ROOT_DIR/store_assets/play_store_icon_512.png"
FONT="/System/Library/Fonts/Supplemental/Arial Unicode.ttf"
OUT_DIR="$ROOT_DIR/store_assets/screenshots"

if ! command -v magick >/dev/null 2>&1; then
  echo "ImageMagick 'magick' is required." >&2
  exit 1
fi

if [[ ! -f "$ICON" ]]; then
  echo "Missing icon: $ICON" >&2
  exit 1
fi

mkdir -p "$OUT_DIR/android_phone" "$OUT_DIR/ios_6_7"

draw_screenshot() {
  local width="$1"
  local height="$2"
  local output="$3"
  local title="$4"
  local subtitle_one="$5"
  local subtitle_two="$6"
  local card_title="$7"
  local card_body_one="$8"
  local card_body_two="$9"
  local footer="${10}"
  local accent="${11}"

  local margin=$((width / 12))
  local top=$((height / 16))
  local icon_size=$((width / 3 + width / 18))
  local icon_x=$(((width - icon_size) / 2))
  local icon_y=$((top + height / 7))
  local card_x=$margin
  local card_y=$((height * 3 / 5))
  local card_w=$((width - margin * 2))
  local card_h=$((height / 4))
  local card_r=$((width / 26))
  local title_size=$((width / 14))
  local subtitle_size=$((width / 28))
  local body_size=$((width / 34))
  local chip_y=$((card_y + card_h + height / 22))

  magick -size "${width}x${height}" xc:'#FFF8EA' \
    -fill '#D7F1EC' -draw "circle $((width * 4 / 5)),$((height / 7)) $((width + width / 4)),$((height / 7))" \
    -fill '#FFE4A8' -draw "circle $((width / 5)),$((height * 4 / 5)) $((width / 2)),$((height * 4 / 5))" \
    -fill "$accent" -draw "circle $((width + width / 10)),$((height * 5 / 6)) $((width + width / 3)),$((height * 5 / 6))" \
    -font "$FONT" \
    -fill '#1F5F5A' -pointsize "$title_size" -weight 700 -draw "text $margin,$((top + title_size)) '$title'" \
    -fill '#2C5652' -pointsize "$subtitle_size" -weight 500 -draw "text $margin,$((top + title_size + subtitle_size * 2)) '$subtitle_one'" \
    -fill '#2C5652' -pointsize "$subtitle_size" -weight 500 -draw "text $margin,$((top + title_size + subtitle_size * 3 + height / 80)) '$subtitle_two'" \
    \( "$ICON" -resize "${icon_size}x${icon_size}" \) -geometry +"$icon_x"+"$icon_y" -composite \
    -fill '#FFFFFF' -draw "roundrectangle $card_x,$card_y $((card_x + card_w)),$((card_y + card_h)) $card_r,$card_r" \
    -fill '#1F5F5A' -pointsize "$subtitle_size" -weight 700 -draw "text $((card_x + margin / 2)),$((card_y + subtitle_size * 2)) '$card_title'" \
    -fill '#5F706E' -pointsize "$body_size" -weight 400 -draw "text $((card_x + margin / 2)),$((card_y + subtitle_size * 2 + body_size * 2)) '$card_body_one'" \
    -fill '#5F706E' -pointsize "$body_size" -weight 400 -draw "text $((card_x + margin / 2)),$((card_y + subtitle_size * 2 + body_size * 3 + height / 90)) '$card_body_two'" \
    -fill '#F3C85E' -draw "roundrectangle $margin,$chip_y $((width - margin)),$((chip_y + height / 18)) $((height / 54)),$((height / 54))" \
    -fill '#214B48' -pointsize "$body_size" -weight 600 -draw "text $((margin + margin / 2)),$((chip_y + body_size + height / 70)) '$footer'" \
    "$output"
}

make_set() {
  local width="$1"
  local height="$2"
  local folder="$3"

  draw_screenshot "$width" "$height" "$folder/01_home_voice.png" \
    "AI陪伴" \
    "對著寵物說話" \
    "陪伴就從這裡開始" \
    "大麥克風，一按就開始" \
    "首頁保留寵物、狀態與語音按鈕。" \
    "長者不用找功能，也能安心開始。" \
    "簡單操作・清楚陪伴" \
    "#F8C9B4"

  draw_screenshot "$width" "$height" "$folder/02_voice_conversation.png" \
    "用說的，就有人陪" \
    "寵物會聽你說" \
    "也用溫暖語氣回應" \
    "即時語音陪伴" \
    "支援語音互動與台灣日常語氣。" \
    "讓對話更像熟悉的陪伴。" \
    "語音互動・自然回覆" \
    "#C8E8D2"

  draw_screenshot "$width" "$height" "$folder/03_memory.png" \
    "記得重要的小事" \
    "喜歡的稱呼與家人" \
    "生活習慣都能慢慢累積" \
    "長期記憶" \
    "AI 寵物記得有陪伴價值的內容。" \
    "讓下次聊天更自然、更貼心。" \
    "記憶可查看・可刪除" \
    "#D8D4F2"

  draw_screenshot "$width" "$height" "$folder/04_care_alert.png" \
    "溫和的關懷提醒" \
    "需要多一點關心時" \
    "協助照護者留意狀況" \
    "Care Alert" \
    "這是照護輔助提醒，不是醫療診斷。" \
    "也不取代醫師或專業判斷。" \
    "照護參考・非醫療診斷" \
    "#FFD7B5"

  draw_screenshot "$width" "$height" "$folder/05_privacy_support.png" \
    "資料由你作主" \
    "隱私、條款與支援" \
    "帳號刪除都放在設定裡" \
    "隱私與支援" \
    "可查看同意內容、聯絡客服。" \
    "也能申請刪除帳號與資料。" \
    "客服信箱已公開・支援資料刪除" \
    "#BFE5E1"
}

make_set 1080 1920 "$OUT_DIR/android_phone"
make_set 1290 2796 "$OUT_DIR/ios_6_7"

echo "Generated store screenshots in $OUT_DIR"
