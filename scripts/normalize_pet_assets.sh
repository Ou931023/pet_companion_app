#!/usr/bin/env bash
#
# CR-0075 寵物素材規格化（1024×1024 / 透明 / 置中）
# -----------------------------------------------------------------------------
# 目的：把現有寵物素材統一成正式展示規格，不新增/生成任何缺圖，只重處理既有素材。
#
# 需要工具（擇一）：
#   ImageMagick 7 → 指令 `magick`        建議：brew install imagemagick
#   ImageMagick 6 → 指令 `convert`
#
# 設計重點（避免動畫跳動）：
#   - 同一隻寵物用「同一組裁切/縮放參數」套用到所有 frame（以 states/normal 當基準框），
#     讓主體比例與位置固定，只有姿勢變化 → talk/rest 不會抖。
#   - 去背用「四角 floodfill」而非整片刪白，避免吃掉肚子的白毛。
#   - 產出到 assets/pets_normalized/，不覆蓋原檔；另產 _review_montage.png 供肉眼檢查。
#
# 用法：
#   bash scripts/normalize_pet_assets.sh           # 全部寵物
#   bash scripts/normalize_pet_assets.sh dog       # 只處理單一寵物
#
# 規格參數（可依檢查結果微調）：
CANVAS=1024            # 畫布邊長
BODY_H=780            # 中性站姿主體目標高度（規格 780~860，取下緣保留舉手往上的空間）
BOTTOM_PAD=80         # 下方留白（腳底到底邊），規格 60~100
# -----------------------------------------------------------------------------
set -euo pipefail
cd "$(dirname "$0")/.."

# --- 選擇 ImageMagick 指令 ---------------------------------------------------
if command -v magick >/dev/null 2>&1; then IM="magick";
elif command -v convert >/dev/null 2>&1; then IM="convert";
else
  echo "找不到 ImageMagick。請先安裝：brew install imagemagick" >&2
  exit 1
fi
echo "使用 ImageMagick 指令：$IM"

SRC="assets/pets"
OUT="assets/pets_normalized"
rm -rf "$OUT"
mkdir -p "$OUT/talk" "$OUT/rest" "$OUT/listening" "$OUT/states"

# 各寵物實際擁有的張數（與 lib/utils/asset_paths.dart 一致；
# 刻意不含 guinea_pig_talk_04/05/06：那 3 張是壞檔（烤進去的透明網格）且風格/比例不符）。
declare -A TALK=( [dog]=6 [fox]=6 [guinea_pig]=3 )
declare -A REST=( [dog]=3 [fox]=3 [guinea_pig]=3 )
STATES=(normal happy caring excited hungry thirsty sleepy sad)

PETS=("$@")
[ ${#PETS[@]} -eq 0 ] && PETS=(dog fox guinea_pig)

FUZZ=12%   # 去背容差（白底毛邊用；太大會吃毛、太小留白邊）

# 去背：四角 floodfill（dog 已透明也無妨，從透明角起不會擴散）。
debg() {  # $1 in  $2 out
  $IM "$1" -alpha set -fuzz "$FUZZ" -fill none \
      -draw "alpha 0,0 floodfill" \
      -draw "alpha %[fx:w-1],0 floodfill" \
      -draw "alpha 0,%[fx:h-1] floodfill" \
      -draw "alpha %[fx:w-1],%[fx:h-1] floodfill" \
      "$2"
}

# 把單張圖規格化：去背 → 修邊 → 用「該寵物固定縮放比例」縮放 → 以腳底為錨點置中補到 1024²。
#   固定縮放比例（同一隻所有 frame 共用）是不跳動的關鍵：
#   主體實體大小一致、腳底對齊同一條線，舉手/動態線只會往上延伸而非把身體縮小。
# $1 來源檔  $2 輸出檔  $3 縮放百分比（例 145 表示放大到 145%）
normalize_one() {
  local in="$1" out="$2" scale_pct="$3"
  debg "$in" "$out.tmp.png"
  # 修邊 → 固定比例縮放 → 腳底加留白 → 以南（底部置中）為錨點 extent 到 1024²。
  #   gravity south：鎖定底部、水平置中、向上補/裁（必要時只裁到舉手的指尖，不動身體）。
  $IM "$out.tmp.png" -trim +repage \
      -resize "${scale_pct}%" \
      -background none -gravity south -splice 0x${BOTTOM_PAD} \
      -gravity south -extent ${CANVAS}x${CANVAS} \
      -define png:color-type=6 \
      "$out"
  rm -f "$out.tmp.png"
}

# 算某寵物的固定縮放比例：用 states/normal（中性站姿）去背修邊後的「內容高度」，
# 換算成讓主體高度 ≈ BODY_H 的百分比。回傳整數百分比。
scale_for() {
  local pet="$1" ref="$SRC/states/${pet}_normal.png"
  [ -f "$ref" ] || { echo 100; return; }
  debg "$ref" "/tmp/_cr0075_ref.png"
  local hc
  hc=$($IM "/tmp/_cr0075_ref.png" -trim -format "%h" info: 2>/dev/null)
  rm -f "/tmp/_cr0075_ref.png"
  [ -z "$hc" ] && { echo 100; return; }
  # 百分比 = BODY_H / Hc * 100，用整數運算。
  echo $(( BODY_H * 100 / hc ))
}

for pet in "${PETS[@]}"; do
  scale=$(scale_for "$pet")          # 該寵物固定縮放比例（所有 frame 共用 → 不跳動）
  echo "== 處理 ${pet}（固定縮放 ${scale}%）=="

  for i in $(seq 1 "${TALK[$pet]}"); do
    n=$(printf "%02d" "$i")
    [ -f "$SRC/talk/${pet}_talk_${n}.png" ] && \
      normalize_one "$SRC/talk/${pet}_talk_${n}.png" "$OUT/talk/${pet}_talk_${n}.png" "$scale"
  done
  for i in $(seq 1 "${REST[$pet]}"); do
    n=$(printf "%02d" "$i")
    [ -f "$SRC/rest/${pet}_rest_${n}.png" ] && \
      normalize_one "$SRC/rest/${pet}_rest_${n}.png" "$OUT/rest/${pet}_rest_${n}.png" "$scale"
  done
  [ -f "$SRC/listening/${pet}_listening.png" ] && \
    normalize_one "$SRC/listening/${pet}_listening.png" "$OUT/listening/${pet}_listening.png" "$scale"
  for s in "${STATES[@]}"; do
    [ -f "$SRC/states/${pet}_${s}.png" ] && \
      normalize_one "$SRC/states/${pet}_${s}.png" "$OUT/states/${pet}_${s}.png" "$scale"
  done
done

# 產出檢查用 montage（把所有輸出排成一張，肉眼檢查比例/置中/去背/跳動）。
echo "== 產出檢查圖 $OUT/_review_montage.png =="
if command -v montage >/dev/null 2>&1; then
  montage "$OUT"/states/*.png "$OUT"/talk/*.png "$OUT"/rest/*.png \
    -tile 8x -geometry 128x128+2+2 -background gray70 \
    "$OUT/_review_montage.png" || true
fi

echo ""
echo "完成。請打開 $OUT/ 逐張檢查（特別看：去背乾不乾淨、主體比例一致、腳底對齊、talk/rest 不跳）。"
echo "確認 OK 後再執行搬移（會覆蓋正式 assets/pets/）。本腳本不自動覆蓋。"
