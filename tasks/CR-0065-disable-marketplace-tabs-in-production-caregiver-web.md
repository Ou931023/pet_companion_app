# CR-0065 Disable Marketplace Tabs in Production caregiver_web

## 背景

Render production 後端與 caregiver_web 已成功部署，CORS 已修正，caregiver_web 現在可打到正確後端：

- Backend: https://ai-companion-app-7mb8.onrender.com
- Caregiver Web: https://ai-companion-caregiver-web.onrender.com

但管理者登入後仍卡在「正在以管理者身分載入資料...」。

Browser Console 顯示新的錯誤，不再是 CORS，而是：

```text
Failed to load resource: the server responded with a status of 501
https://ai-companion-app-7mb8.onrender.com/api/marketplace/products?status=all

Failed to load resource: the server responded with a status of 501
https://ai-companion-app-7mb8.onrender.com/api/admin/marketplace/orders
