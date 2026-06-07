<!--# CR-0021 Conversation Record Delete 任務檔

## 目標

對話紀錄需要支援刪除單筆紀錄。使用者長按某一筆對話紀錄後，可以刪除該筆紀錄。

## 使用者互動

流程：

1. 使用者在對話紀錄 / 聊天紀錄中長按某一筆訊息。
2. 顯示確認視窗。
3. 文案：要刪除這筆紀錄嗎？
4. 按鈕：取消 / 刪除。
5. 點「刪除」後移除該筆紀錄。
6. 不要長按後直接刪除，避免誤觸。

## 重要定義

對話紀錄刪除不等於長期記憶刪除。

- 對話紀錄：聊天歷史中的單筆訊息。
- 長期記憶：MemoryService 抽取後保存的重要資訊。

本次只處理對話紀錄刪除，不要刪長期記憶。

## 實作要求

1. 找出對話紀錄顯示頁面或聊天訊息列表。
2. 找出 conversation message model / controller / local storage。
3. 新增刪除單筆對話紀錄的方法。
4. 若已有 archive/delete 機制，請沿用。
5. 若目前只有前端本地紀錄，先刪本地紀錄。
6. 刪除後 UI 要即時更新。
7. 若刪除失敗，顯示白話錯誤訊息。
8. 不要刪除 MemoryService 中的長期記憶。
9. 不要影響 Realtime 對話流程。

## 禁止修改

不要混入：
- Realtime 主流程
- Agent tools
- MemoryService 長期記憶刪除
- onboarding
- pet skin
- auth/admin
- runtime data
- raw assets

## 測試

請加入或更新測試：

1. 長按訊息會出現確認視窗。
2. 點取消不刪除。
3. 點刪除會移除該筆訊息。
4. 只刪除指定訊息，不影響其他訊息。
5. 不會刪除長期記憶。
6. flutter analyze 通過。
7. flutter test 通過。

## Commit

commit message：

CR-0021 conversation record delete

不要 push。

## 回報

請回報：
- 對話紀錄原本存在哪裡
- 如何長按刪除
- 是否有確認視窗
- 是否影響長期記憶
- 修改檔案
- 測試結果
- commit hash>