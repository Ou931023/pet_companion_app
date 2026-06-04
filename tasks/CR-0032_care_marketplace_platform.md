<!--# CR-0032 長照商品商城平台 MVP

## 一、背景

目前 App 的商城只是外部連結到維康照護用品網站：

https://www.wellcare.com.tw/wellcare/tw

現在要把商城升級成我們自己的長照商品平台。

新的概念是：

1. 長照中心／長照人員可以在管理端上架商品。
2. 商品會顯示在長者端 App 的商城頁。
3. 使用者可以在 App 中下單商品。
4. 平台方收到訂單後，協助聯絡、出貨或配送。
5. 商品銷售金額會與長照中心拆帳，平台從中抽成。
6. 整體概念類似蝦皮、momo 第三方賣家平台，但主題限定在長照用品、健康照護用品、生活輔助用品。

本 CR 不串接真正金流、不串接外部維康 API、不爬蟲。先做可 Demo 的 Marketplace MVP。

---

## 二、CR-0032 目標

建立長照商品商城平台 MVP，完成：

1. 管理端商品管理
2. 長者端內建商城
3. 購物車
4. 建立訂單
5. 管理端訂單管理
6. 平台抽成金額計算
7. Demo 種子商品資料

核心展示流程：

管理端上架商品 → 長者端 App 看到商品 → 加入購物車 → 建立訂單 → 管理端看到訂單 → 顯示平台抽成與長照中心實收。

---

## 三、管理端商品管理 caregiver_web

請在 `caregiver_web` 新增「商品管理」頁面。

功能包含：

- 商品列表
- 新增商品
- 編輯商品
- 商品上下架
- 商品分類
- 商品庫存
- 商品價格
- 商品圖片 URL
- 商品所屬長照中心名稱
- 平台抽成比例設定

商品欄位至少包含：

```txt
product_id
center_id
center_name
name
description
category
price
stock
image_url
status: active / inactive
commission_rate
created_at
updated_at
商品分類固定選項：
照護用品
復健輔具
營養補充
清潔衛生
日常生活
其他
後台 UI 要與目前 caregiver_web 風格一致，看起來像正式管理端。
四、長者端 App 商城頁 Flutter
目前商城若只是外部連結，請改成內建商城頁。
長者端需要：
顯示商品列表
顯示商品圖片、名稱、價格、分類、庫存狀態
商品詳情頁
加入購物車
調整數量
建立訂單
缺貨不可下單
下單成功頁
長者端文案要簡單、白話、不要工程化。
可使用文案：
照護用品商城
挑選需要的用品，我們會協助通知照護中心處理訂單。

加入購物車
確認下單
訂單已送出，我們會盡快協助處理。
五、購物車功能
Flutter App 加入購物車功能。
至少包含：
加入商品
移除商品
調整數量
計算小計
計算總金額
確認下單
購物車資料可先存在 App 狀態中。若目前專案已有 local storage 架構，可以同步保存。
六、訂單功能
後端新增訂單 API，讓 App 可以建立訂單，管理端可以查看訂單。
訂單欄位至少包含：
order_id
user_id
elder_name
center_id
center_name
items
total_amount
commission_amount
center_revenue
status
delivery_note
created_at
updated_at
訂單狀態：
pending        待處理
confirmed      已確認
shipping       配送中
completed      已完成
cancelled      已取消
items 內至少包含：
product_id
product_name
quantity
unit_price
subtotal
抽成計算方式：
commission_amount = total_amount * commission_rate
center_revenue = total_amount - commission_amount
MVP 階段可以限制一次訂單只購買同一長照中心商品，避免拆單邏輯太複雜。
七、管理端訂單管理 caregiver_web
請在 caregiver_web 新增「訂單管理」頁面。
功能包含：
訂單列表
訂單詳情
顯示購買人／長者名稱
顯示商品明細
顯示總金額
顯示平台抽成
顯示長照中心實收金額
修改訂單狀態
填寫配送備註
訂單列表狀態篩選：
全部
待處理
已確認
配送中
已完成
已取消
訂單詳情需明確顯示：
商品總金額：NT$ 2,500
平台抽成：NT$ 250
長照中心實收：NT$ 2,250
八、後端 API 需求
請在後端新增 marketplace API。
若目前專案已有 service/store 分層，請遵守既有架構，不要全部塞在 server.js。
商品 API
GET    /api/marketplace/products
GET    /api/marketplace/products/:id
POST   /api/admin/marketplace/products
PUT    /api/admin/marketplace/products/:id
PATCH  /api/admin/marketplace/products/:id/status
訂單 API
POST   /api/marketplace/orders
GET    /api/admin/marketplace/orders
GET    /api/admin/marketplace/orders/:id
PATCH  /api/admin/marketplace/orders/:id/status
管理者 API 要沿用目前 requireAdmin 權限保護。
九、資料儲存要求
正式方向是 PostgreSQL。
如果目前專案已有 JSON fallback，可以保留 fallback 方便 Demo，但不要破壞既有資料表與功能。
新增資料表設計：
marketplace_products
id
center_id
center_name
name
description
category
price
stock
image_url
status
commission_rate
created_at
updated_at
marketplace_orders
id
user_id
elder_name
center_id
center_name
items_json
total_amount
commission_amount
center_revenue
status
delivery_note
created_at
updated_at
請新增 migration 或 SQL schema 文件，依照目前專案命名規則。
十、Flutter 建議新增檔案
依照目前 Flutter 架構新增或調整。
可能需要新增：
lib/models/marketplace_product.dart
lib/models/marketplace_order.dart
lib/models/cart_item.dart

lib/services/marketplace_service.dart

lib/controllers/marketplace_controller.dart
lib/controllers/cart_controller.dart

lib/screens/marketplace/marketplace_screen.dart
lib/screens/marketplace/product_detail_screen.dart
lib/screens/marketplace/cart_screen.dart
lib/screens/marketplace/order_success_screen.dart
如果目前專案已有 routes 架構，請掛到現有路由。
商城入口請放在目前 App 的商城入口或底部導覽商城頁，不要新增太多重複入口。
十一、Demo 種子資料
請加入幾筆 Demo 商品，方便展示。
1. 防滑沐浴椅
分類：照護用品
價格：1800
庫存：12
長照中心：安心長照中心
抽成比例：0.10

2. 助行器
分類：復健輔具
價格：2500
庫存：6
長照中心：安心長照中心
抽成比例：0.10

3. 高蛋白營養飲
分類：營養補充
價格：899
庫存：20
長照中心：康福長照中心
抽成比例：0.12

4. 成人紙尿褲
分類：清潔衛生
價格：650
庫存：30
長照中心：康福長照中心
抽成比例：0.12
圖片可以先使用 placeholder image URL 或本地 assets，但畫面不可破圖。
十二、限制事項
請遵守：
不串接真正金流。
不串接外部維康網站 API。
不爬取維康網站資料。
不破壞 Realtime 語音功能。
不破壞 Care Alert 功能。
不破壞登入註冊流程。
不破壞寵物換皮功能。
長者端不要顯示工程化錯誤訊息。
不要把 exception、stack trace、API error 直接顯示在畫面上。
所有長者端文案要口語、簡單、清楚。
十三、測試與完成回報
完成後請執行：
flutter analyze
flutter test
後端依照 package.json 執行：
npm test
npm run check
若測試環境有限，至少確認：
App 可以正常開啟。
商城頁可以載入商品。
商品可以加入購物車。
可以建立訂單。
管理端可以看到訂單。
管理端可以新增商品。
管理端可以修改訂單狀態。
既有 Care Alert、Realtime、登入頁沒有被破壞。
完成後請用以下格式回報：
CR-0032 完成回報

一、完成內容

二、新增功能
- 長者端商城
- 購物車
- 訂單建立
- 管理端商品管理
- 管理端訂單管理
- 抽成計算

三、修改檔案

四、新增檔案

五、API 路由

六、資料表 / 資料儲存

七、測試結果

八、Demo 操作流程

九、尚未做的正式版功能-->