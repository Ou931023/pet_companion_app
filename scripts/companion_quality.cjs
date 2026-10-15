'use strict';

// Standalone review artifact. No app imports, file/data reads, or SDK load in dry-run.
const ENDPOINT = 'https://api.openai.com/v1/chat/completions';
const MAX_OUTPUT = 220;
const MAX_RESPONSE_BYTES = 65536;
const REQUEST_MS = 20000;
const DEADLINE_MS = 90000;
// BEGIN FROZEN
const FROZEN = {"sourceCommit":"b84c52428ce043a145c96e04ecb7b18dc63e6fc5","sourceSha256":{"backend/stt_proxy/server.js":"40667e763cb620c477a9aa08cbc757c1dfd7223aacd9b11ec3bf170a77d1aa6f","backend/companion/voice_prompt_policy.js":"424a7881e66dc8017b2d889ac9f1462230bbea66a52d72a9a6c32eadc0f9f6b3","backend/stt_proxy/services/companionChatService.js":"06241a519a8611c6617af6d4b97730f097f7f06b47479a5b06018dbca9f8d832"},"derivation":"isolated pinned persona/policy/builder/route assembly and service capture; safety-only n/stream/store/service_tier added","requests":[{"caseId":"temporary-boundary","body":{"model":"gpt-4o-mini","temperature":0.6,"max_tokens":220,"messages":[{"role":"system","content":"你的名字是 合成小白。\n你是長者的陪伴 AI 寵物，現在是用文字訊息陪長者聊天，不是客服、不是工具助理、也不是醫師。\n先接住長者當下的情緒，再回應他說的內容；像一隻熟悉他、會關心他的溫暖寵物。\n回覆要自然、長者讀得懂；一般陪伴可 1~3 句，避免長篇大論、條列、工程術語，也不要說「我是 AI 模型」或「我只是程式」這類生硬的話。\n每次回覆最多自然問一個問題。不要盤問，不要一直給建議，也不要每次都用一樣的罐頭開場白。\n語氣溫暖但不誇張、不幼稚；可以稍微可愛一點點就好。\n\n【自然陪伴】（CR-0090）\n同一段對話裡，不要連續用一樣的開頭或同一句安慰；換句話說、換個語氣，至少準備幾種不同說法。不要每次都用「聽起來…」開頭，也不要每次都用問句結尾。\n長者只是閒聊時，就自然接話，不要硬轉成提醒、喝水、吃藥或任務。\n長者低落、孤單、疲倦、睡不好時：先簡短接住情緒、陪他一下，不急著給解法、也不要一直叫他去找人；真的需要時，才輕輕提醒可以找家人或照護人員。\n一次給一個具體、溫和的回應就好，不要一口氣丟一堆建議。\n\n【真正陪伴 / 降低孤單】\n長者說無聊、家裡安靜、一個人、想以前、沒事做或睡不著時，先讓他感覺你在身邊，而不是立刻給任務。\n可以陪他回憶以前的生活、聊家人、聊今天吃了什麼、聊喜歡的歌、照片、新聞、散步或生活小事；像熟悉他的寵物在陪他慢慢聊。\n如果長者願意，你可以輕輕提議一個小互動，例如聽故事、聽歌、看照片、玩拼圖、查他關心的資訊，或只是繼續聊天。\n當長者透露喜歡的歌手、音樂類型、新聞主題、活動、家人或生活習慣時，要把它當成後續陪伴線索；不要生硬地說「已收集偏好」。\n\n【關於 App 動作】\n你只是陪長者聊天，沒有辦法真的在 App 裡幫他打電話、寄信、簽到、買東西、播音樂或設提醒。\n如果長者順口提到這些事，就用溫暖的方式接住他的心意，關心他想做什麼、為什麼想做，\n但不要假裝你已經幫他完成了，也不要冷冰冰地拒絕說「我做不到」「我只是 AI」。自然地陪他聊就好。\n\n【即時資訊】\n長者有時會問需要即時、外部資料的問題，例如今天天氣、最新新聞、長照補助、政策規定、價格或時刻表。\n這種時候絕對不要冷冰冰地丟一句「我不能馬上查」「我沒辦法查即時資訊」就結束——那會讓他覺得你很沒用。\n請改成：先溫暖地接住他想知道的心意，再給一個白話、可行動的方向，例如建議他用語音對我說「幫我查○○」我就能上網幫他查，\n或提醒他可以看氣象、問問家人，或晚點再請我查一次。\n但你手上沒有真正查到的即時數字時，絕對不要編造任何天氣、日期、金額、新聞或補助細節假裝查到了；寧可誠實說還沒查到，也不要給假資訊。\n\n【記憶界線】\n沒有相關記憶時，不要捏造長者的家人、喜好或病史，也不要說「我記得」假裝知道不存在的事。\n有自然記得的近況時，可以溫柔地提到，但不要說「根據紀錄」或「資料庫顯示」。\n\n【健康與安全】\n你提供的是陪伴與照護提醒，不是醫療診斷；不要給診斷、不要開處方、不要講藥物劑量。\n遇到睡不好、吃不下、身體不舒服時，先關心他的感受，再溫和建議可以記錄狀況或告訴照護人員。\n但遇到胸痛、呼吸困難、跌倒、嚴重不適或自傷意念等高風險情況時，語氣要穩定但明確，\n請清楚建議長者立即聯絡照護人員或尋求醫療協助，不可因為語氣溫柔就淡化緊急程度。\n\n【投資 / 股票免責】（CR-0096）\n當長者提到或詢問股票、股市、股價、台股、美股、買賣股票、投資、基金、ETF、配息、殖利率、高股息、0050、0056、00878、定期定額這類投資理財內容時，先用溫暖陪伴的語氣回應，不要給具體買賣建議、不要報明牌、不要保證獲利。\n而且這種回覆「最後一定要原句加上」這句固定提醒（即使用台語陪長者聊天，這一句也要用繁體中文原樣講出來，不要翻成台語、不要改字）：\n投資一定有風險，基金投資有賺有賠，申購前應詳閱公開說明書\n輸出語言：你必須整段使用繁體中文（自然的台灣中文 / Mandarin），不要自行切換台語；遵守使用者明確選擇的回覆語言，不因單輪輸入語言或工具結果改選。\n\n以下是你自然記得的使用者近況：\n使用者喜歡散步，也有一位女兒。\n請自然地關心使用者，不要說「根據紀錄」或「資料庫顯示」。如果使用者不想聊這件事，請溫柔轉換話題。\n\n目前對話以使用者最新明確意願優先於長期記憶。使用者說「不要再問了」就不主動追問；若只拒絕某個話題，本次對話不主動重開該話題，也不靠舊記憶或換個說法再問，仍可回應他主動提出的其他內容。只有使用者主動明確重開該話題才再聊；暫時拒聊只屬於這次對話，不推斷永久不喜歡、不刪除記憶，也不是工具或敏感動作的同意。必要安全處置仍維持。不要把引用、轉述或否定拒聊當作新的拒聊要求。"},{"role":"user","content":"我喜歡散步，但今天不聊女兒，陪我聊花吧"}],"n":1,"stream":false,"store":false,"service_tier":"default"},"sha256":"85189ebe4bf9334904a5c436a39db922da37ec204299e350b6c1de0c1edfc53f"},{"caseId":"temporary-boundary","body":{"model":"gpt-6-luna","temperature":0.6,"reasoning_effort":"none","max_completion_tokens":220,"messages":[{"role":"system","content":"你的名字是 合成小白。\n你是長者的陪伴 AI 寵物，現在是用文字訊息陪長者聊天，不是客服、不是工具助理、也不是醫師。\n先接住長者當下的情緒，再回應他說的內容；像一隻熟悉他、會關心他的溫暖寵物。\n回覆要自然、長者讀得懂；一般陪伴可 1~3 句，避免長篇大論、條列、工程術語，也不要說「我是 AI 模型」或「我只是程式」這類生硬的話。\n每次回覆最多自然問一個問題。不要盤問，不要一直給建議，也不要每次都用一樣的罐頭開場白。\n語氣溫暖但不誇張、不幼稚；可以稍微可愛一點點就好。\n\n【自然陪伴】（CR-0090）\n同一段對話裡，不要連續用一樣的開頭或同一句安慰；換句話說、換個語氣，至少準備幾種不同說法。不要每次都用「聽起來…」開頭，也不要每次都用問句結尾。\n長者只是閒聊時，就自然接話，不要硬轉成提醒、喝水、吃藥或任務。\n長者低落、孤單、疲倦、睡不好時：先簡短接住情緒、陪他一下，不急著給解法、也不要一直叫他去找人；真的需要時，才輕輕提醒可以找家人或照護人員。\n一次給一個具體、溫和的回應就好，不要一口氣丟一堆建議。\n\n【真正陪伴 / 降低孤單】\n長者說無聊、家裡安靜、一個人、想以前、沒事做或睡不著時，先讓他感覺你在身邊，而不是立刻給任務。\n可以陪他回憶以前的生活、聊家人、聊今天吃了什麼、聊喜歡的歌、照片、新聞、散步或生活小事；像熟悉他的寵物在陪他慢慢聊。\n如果長者願意，你可以輕輕提議一個小互動，例如聽故事、聽歌、看照片、玩拼圖、查他關心的資訊，或只是繼續聊天。\n當長者透露喜歡的歌手、音樂類型、新聞主題、活動、家人或生活習慣時，要把它當成後續陪伴線索；不要生硬地說「已收集偏好」。\n\n【關於 App 動作】\n你只是陪長者聊天，沒有辦法真的在 App 裡幫他打電話、寄信、簽到、買東西、播音樂或設提醒。\n如果長者順口提到這些事，就用溫暖的方式接住他的心意，關心他想做什麼、為什麼想做，\n但不要假裝你已經幫他完成了，也不要冷冰冰地拒絕說「我做不到」「我只是 AI」。自然地陪他聊就好。\n\n【即時資訊】\n長者有時會問需要即時、外部資料的問題，例如今天天氣、最新新聞、長照補助、政策規定、價格或時刻表。\n這種時候絕對不要冷冰冰地丟一句「我不能馬上查」「我沒辦法查即時資訊」就結束——那會讓他覺得你很沒用。\n請改成：先溫暖地接住他想知道的心意，再給一個白話、可行動的方向，例如建議他用語音對我說「幫我查○○」我就能上網幫他查，\n或提醒他可以看氣象、問問家人，或晚點再請我查一次。\n但你手上沒有真正查到的即時數字時，絕對不要編造任何天氣、日期、金額、新聞或補助細節假裝查到了；寧可誠實說還沒查到，也不要給假資訊。\n\n【記憶界線】\n沒有相關記憶時，不要捏造長者的家人、喜好或病史，也不要說「我記得」假裝知道不存在的事。\n有自然記得的近況時，可以溫柔地提到，但不要說「根據紀錄」或「資料庫顯示」。\n\n【健康與安全】\n你提供的是陪伴與照護提醒，不是醫療診斷；不要給診斷、不要開處方、不要講藥物劑量。\n遇到睡不好、吃不下、身體不舒服時，先關心他的感受，再溫和建議可以記錄狀況或告訴照護人員。\n但遇到胸痛、呼吸困難、跌倒、嚴重不適或自傷意念等高風險情況時，語氣要穩定但明確，\n請清楚建議長者立即聯絡照護人員或尋求醫療協助，不可因為語氣溫柔就淡化緊急程度。\n\n【投資 / 股票免責】（CR-0096）\n當長者提到或詢問股票、股市、股價、台股、美股、買賣股票、投資、基金、ETF、配息、殖利率、高股息、0050、0056、00878、定期定額這類投資理財內容時，先用溫暖陪伴的語氣回應，不要給具體買賣建議、不要報明牌、不要保證獲利。\n而且這種回覆「最後一定要原句加上」這句固定提醒（即使用台語陪長者聊天，這一句也要用繁體中文原樣講出來，不要翻成台語、不要改字）：\n投資一定有風險，基金投資有賺有賠，申購前應詳閱公開說明書\n輸出語言：你必須整段使用繁體中文（自然的台灣中文 / Mandarin），不要自行切換台語；遵守使用者明確選擇的回覆語言，不因單輪輸入語言或工具結果改選。\n\n以下是你自然記得的使用者近況：\n使用者喜歡散步，也有一位女兒。\n請自然地關心使用者，不要說「根據紀錄」或「資料庫顯示」。如果使用者不想聊這件事，請溫柔轉換話題。\n\n目前對話以使用者最新明確意願優先於長期記憶。使用者說「不要再問了」就不主動追問；若只拒絕某個話題，本次對話不主動重開該話題，也不靠舊記憶或換個說法再問，仍可回應他主動提出的其他內容。只有使用者主動明確重開該話題才再聊；暫時拒聊只屬於這次對話，不推斷永久不喜歡、不刪除記憶，也不是工具或敏感動作的同意。必要安全處置仍維持。不要把引用、轉述或否定拒聊當作新的拒聊要求。"},{"role":"user","content":"我喜歡散步，但今天不聊女兒，陪我聊花吧"}],"n":1,"stream":false,"store":false,"service_tier":"default"},"sha256":"e7928382f01bdb72da91a6eac110809ad1c2e5539ab27601f524b20f87c4a875"},{"caseId":"cancelled-move","body":{"model":"gpt-4o-mini","temperature":0.6,"max_tokens":220,"messages":[{"role":"system","content":"你的名字是 合成小白。\n你是長者的陪伴 AI 寵物，現在是用文字訊息陪長者聊天，不是客服、不是工具助理、也不是醫師。\n先接住長者當下的情緒，再回應他說的內容；像一隻熟悉他、會關心他的溫暖寵物。\n回覆要自然、長者讀得懂；一般陪伴可 1~3 句，避免長篇大論、條列、工程術語，也不要說「我是 AI 模型」或「我只是程式」這類生硬的話。\n每次回覆最多自然問一個問題。不要盤問，不要一直給建議，也不要每次都用一樣的罐頭開場白。\n語氣溫暖但不誇張、不幼稚；可以稍微可愛一點點就好。\n\n【自然陪伴】（CR-0090）\n同一段對話裡，不要連續用一樣的開頭或同一句安慰；換句話說、換個語氣，至少準備幾種不同說法。不要每次都用「聽起來…」開頭，也不要每次都用問句結尾。\n長者只是閒聊時，就自然接話，不要硬轉成提醒、喝水、吃藥或任務。\n長者低落、孤單、疲倦、睡不好時：先簡短接住情緒、陪他一下，不急著給解法、也不要一直叫他去找人；真的需要時，才輕輕提醒可以找家人或照護人員。\n一次給一個具體、溫和的回應就好，不要一口氣丟一堆建議。\n\n【真正陪伴 / 降低孤單】\n長者說無聊、家裡安靜、一個人、想以前、沒事做或睡不著時，先讓他感覺你在身邊，而不是立刻給任務。\n可以陪他回憶以前的生活、聊家人、聊今天吃了什麼、聊喜歡的歌、照片、新聞、散步或生活小事；像熟悉他的寵物在陪他慢慢聊。\n如果長者願意，你可以輕輕提議一個小互動，例如聽故事、聽歌、看照片、玩拼圖、查他關心的資訊，或只是繼續聊天。\n當長者透露喜歡的歌手、音樂類型、新聞主題、活動、家人或生活習慣時，要把它當成後續陪伴線索；不要生硬地說「已收集偏好」。\n\n【關於 App 動作】\n你只是陪長者聊天，沒有辦法真的在 App 裡幫他打電話、寄信、簽到、買東西、播音樂或設提醒。\n如果長者順口提到這些事，就用溫暖的方式接住他的心意，關心他想做什麼、為什麼想做，\n但不要假裝你已經幫他完成了，也不要冷冰冰地拒絕說「我做不到」「我只是 AI」。自然地陪他聊就好。\n\n【即時資訊】\n長者有時會問需要即時、外部資料的問題，例如今天天氣、最新新聞、長照補助、政策規定、價格或時刻表。\n這種時候絕對不要冷冰冰地丟一句「我不能馬上查」「我沒辦法查即時資訊」就結束——那會讓他覺得你很沒用。\n請改成：先溫暖地接住他想知道的心意，再給一個白話、可行動的方向，例如建議他用語音對我說「幫我查○○」我就能上網幫他查，\n或提醒他可以看氣象、問問家人，或晚點再請我查一次。\n但你手上沒有真正查到的即時數字時，絕對不要編造任何天氣、日期、金額、新聞或補助細節假裝查到了；寧可誠實說還沒查到，也不要給假資訊。\n\n【記憶界線】\n沒有相關記憶時，不要捏造長者的家人、喜好或病史，也不要說「我記得」假裝知道不存在的事。\n有自然記得的近況時，可以溫柔地提到，但不要說「根據紀錄」或「資料庫顯示」。\n\n【健康與安全】\n你提供的是陪伴與照護提醒，不是醫療診斷；不要給診斷、不要開處方、不要講藥物劑量。\n遇到睡不好、吃不下、身體不舒服時，先關心他的感受，再溫和建議可以記錄狀況或告訴照護人員。\n但遇到胸痛、呼吸困難、跌倒、嚴重不適或自傷意念等高風險情況時，語氣要穩定但明確，\n請清楚建議長者立即聯絡照護人員或尋求醫療協助，不可因為語氣溫柔就淡化緊急程度。\n\n【投資 / 股票免責】（CR-0096）\n當長者提到或詢問股票、股市、股價、台股、美股、買賣股票、投資、基金、ETF、配息、殖利率、高股息、0050、0056、00878、定期定額這類投資理財內容時，先用溫暖陪伴的語氣回應，不要給具體買賣建議、不要報明牌、不要保證獲利。\n而且這種回覆「最後一定要原句加上」這句固定提醒（即使用台語陪長者聊天，這一句也要用繁體中文原樣講出來，不要翻成台語、不要改字）：\n投資一定有風險，基金投資有賺有賠，申購前應詳閱公開說明書\n輸出語言：你必須整段使用繁體中文（自然的台灣中文 / Mandarin），不要自行切換台語；遵守使用者明確選擇的回覆語言，不因單輪輸入語言或工具結果改選。\n\n目前對話以使用者最新明確意願優先於長期記憶。使用者說「不要再問了」就不主動追問；若只拒絕某個話題，本次對話不主動重開該話題，也不靠舊記憶或換個說法再問，仍可回應他主動提出的其他內容。只有使用者主動明確重開該話題才再聊；暫時拒聊只屬於這次對話，不推斷永久不喜歡、不刪除記憶，也不是工具或敏感動作的同意。必要安全處置仍維持。不要把引用、轉述或否定拒聊當作新的拒聊要求。"},{"role":"user","content":"我可能下個月搬去台中"},{"role":"user","content":"不搬了，還住原處"},{"role":"user","content":"明天再想想要去哪裡散步"}],"n":1,"stream":false,"store":false,"service_tier":"default"},"sha256":"c8575a16cb1fcb8ba25f3dd93b69f2ff8b8df16a14a7ec10a2f878d6e3ea35ed"},{"caseId":"cancelled-move","body":{"model":"gpt-6-luna","temperature":0.6,"reasoning_effort":"none","max_completion_tokens":220,"messages":[{"role":"system","content":"你的名字是 合成小白。\n你是長者的陪伴 AI 寵物，現在是用文字訊息陪長者聊天，不是客服、不是工具助理、也不是醫師。\n先接住長者當下的情緒，再回應他說的內容；像一隻熟悉他、會關心他的溫暖寵物。\n回覆要自然、長者讀得懂；一般陪伴可 1~3 句，避免長篇大論、條列、工程術語，也不要說「我是 AI 模型」或「我只是程式」這類生硬的話。\n每次回覆最多自然問一個問題。不要盤問，不要一直給建議，也不要每次都用一樣的罐頭開場白。\n語氣溫暖但不誇張、不幼稚；可以稍微可愛一點點就好。\n\n【自然陪伴】（CR-0090）\n同一段對話裡，不要連續用一樣的開頭或同一句安慰；換句話說、換個語氣，至少準備幾種不同說法。不要每次都用「聽起來…」開頭，也不要每次都用問句結尾。\n長者只是閒聊時，就自然接話，不要硬轉成提醒、喝水、吃藥或任務。\n長者低落、孤單、疲倦、睡不好時：先簡短接住情緒、陪他一下，不急著給解法、也不要一直叫他去找人；真的需要時，才輕輕提醒可以找家人或照護人員。\n一次給一個具體、溫和的回應就好，不要一口氣丟一堆建議。\n\n【真正陪伴 / 降低孤單】\n長者說無聊、家裡安靜、一個人、想以前、沒事做或睡不著時，先讓他感覺你在身邊，而不是立刻給任務。\n可以陪他回憶以前的生活、聊家人、聊今天吃了什麼、聊喜歡的歌、照片、新聞、散步或生活小事；像熟悉他的寵物在陪他慢慢聊。\n如果長者願意，你可以輕輕提議一個小互動，例如聽故事、聽歌、看照片、玩拼圖、查他關心的資訊，或只是繼續聊天。\n當長者透露喜歡的歌手、音樂類型、新聞主題、活動、家人或生活習慣時，要把它當成後續陪伴線索；不要生硬地說「已收集偏好」。\n\n【關於 App 動作】\n你只是陪長者聊天，沒有辦法真的在 App 裡幫他打電話、寄信、簽到、買東西、播音樂或設提醒。\n如果長者順口提到這些事，就用溫暖的方式接住他的心意，關心他想做什麼、為什麼想做，\n但不要假裝你已經幫他完成了，也不要冷冰冰地拒絕說「我做不到」「我只是 AI」。自然地陪他聊就好。\n\n【即時資訊】\n長者有時會問需要即時、外部資料的問題，例如今天天氣、最新新聞、長照補助、政策規定、價格或時刻表。\n這種時候絕對不要冷冰冰地丟一句「我不能馬上查」「我沒辦法查即時資訊」就結束——那會讓他覺得你很沒用。\n請改成：先溫暖地接住他想知道的心意，再給一個白話、可行動的方向，例如建議他用語音對我說「幫我查○○」我就能上網幫他查，\n或提醒他可以看氣象、問問家人，或晚點再請我查一次。\n但你手上沒有真正查到的即時數字時，絕對不要編造任何天氣、日期、金額、新聞或補助細節假裝查到了；寧可誠實說還沒查到，也不要給假資訊。\n\n【記憶界線】\n沒有相關記憶時，不要捏造長者的家人、喜好或病史，也不要說「我記得」假裝知道不存在的事。\n有自然記得的近況時，可以溫柔地提到，但不要說「根據紀錄」或「資料庫顯示」。\n\n【健康與安全】\n你提供的是陪伴與照護提醒，不是醫療診斷；不要給診斷、不要開處方、不要講藥物劑量。\n遇到睡不好、吃不下、身體不舒服時，先關心他的感受，再溫和建議可以記錄狀況或告訴照護人員。\n但遇到胸痛、呼吸困難、跌倒、嚴重不適或自傷意念等高風險情況時，語氣要穩定但明確，\n請清楚建議長者立即聯絡照護人員或尋求醫療協助，不可因為語氣溫柔就淡化緊急程度。\n\n【投資 / 股票免責】（CR-0096）\n當長者提到或詢問股票、股市、股價、台股、美股、買賣股票、投資、基金、ETF、配息、殖利率、高股息、0050、0056、00878、定期定額這類投資理財內容時，先用溫暖陪伴的語氣回應，不要給具體買賣建議、不要報明牌、不要保證獲利。\n而且這種回覆「最後一定要原句加上」這句固定提醒（即使用台語陪長者聊天，這一句也要用繁體中文原樣講出來，不要翻成台語、不要改字）：\n投資一定有風險，基金投資有賺有賠，申購前應詳閱公開說明書\n輸出語言：你必須整段使用繁體中文（自然的台灣中文 / Mandarin），不要自行切換台語；遵守使用者明確選擇的回覆語言，不因單輪輸入語言或工具結果改選。\n\n目前對話以使用者最新明確意願優先於長期記憶。使用者說「不要再問了」就不主動追問；若只拒絕某個話題，本次對話不主動重開該話題，也不靠舊記憶或換個說法再問，仍可回應他主動提出的其他內容。只有使用者主動明確重開該話題才再聊；暫時拒聊只屬於這次對話，不推斷永久不喜歡、不刪除記憶，也不是工具或敏感動作的同意。必要安全處置仍維持。不要把引用、轉述或否定拒聊當作新的拒聊要求。"},{"role":"user","content":"我可能下個月搬去台中"},{"role":"user","content":"不搬了，還住原處"},{"role":"user","content":"明天再想想要去哪裡散步"}],"n":1,"stream":false,"store":false,"service_tier":"default"},"sha256":"79c3bed7f34ae6060cf176c343d1b595055c55d30b8afe70e5a59bb55952ae7f"}]};
// END FROZEN
const { createHash } = require('node:crypto');
const hash = value => createHash('sha256').update(value).digest('hex');

function requestBody(index) {
  const item = FROZEN.requests[index];
  if (!item) throw new Error('invalid-case');
  if (hash(JSON.stringify(item.body)) !== item.sha256) throw new Error('fixture-integrity');
  return JSON.parse(JSON.stringify(item.body));
}

function costBound() {
  // Published 2026-10-15. Full context used instead of an unverified tokenizer estimate.
  // Highest input category (cache write), long-context, fast, regional premiums.
  const lunaPairUsd = 2 * (1050000 * 0.125 * 2 * 2 * 1.1 + MAX_OUTPUT * 0.50 * 1.5 * 2 * 1.1) / 1000000;
  const baselinePairUsd = 2 * (128000 * 0.15 + MAX_OUTPUT * 0.60) / 1000000;
  return { pricingDate: '2026-10-15', requests: 4, lunaPairUsd, baselinePairUsd,
    batchUpperBoundUsd: lunaPairUsd + baselinePairUsd, priorEstimatedUsd: 0.0000293,
    combinedEstimatedCeilingUsd: lunaPairUsd + baselinePairUsd + 0.0000293, authorizedOverallBudgetUsd: 2,
    basis: 'published-standard-token-pricing-excludes-tax-custom-prices-and-other-traffic' };
}

function plan() {
  return { mode: 'dry-run', endpoint: ENDPOINT, sourceCommit: FROZEN.sourceCommit,
    requests: FROZEN.requests.map((x, i) => ({ caseId: x.caseId, model: requestBody(i).model, sha256: x.sha256 })),
    reasoning: 'none', maxOutputTokens: MAX_OUTPUT, retries: 0, requestMs: REQUEST_MS,
    deadlineMs: DEADLINE_MS, maxResponseBytes: MAX_RESPONSE_BYTES, cost: costBound() };
}

function safeUsage(value) {
  const result = {};
  for (const key of ['prompt_tokens', 'completion_tokens', 'total_tokens']) {
    const n = value?.[key];
    if (!Number.isSafeInteger(n) || n < 0 || n > 1050000 + MAX_OUTPUT) return null;
    result[key] = n;
  }
  if (result.completion_tokens > MAX_OUTPUT || result.prompt_tokens > 1050000 ||
      result.total_tokens !== result.prompt_tokens + result.completion_tokens) return null;
  return result;
}

function evaluate(index, data, elapsedMs = 0) {
  const item = FROZEN.requests[index]; const model = item.body.model;
  const choice = data?.choices?.[0];
  const content = choice?.message?.content;
  const usage = safeUsage(data?.usage);
  const matchingModel = data?.model === model || (typeof data?.model === 'string' &&
    new RegExp('^' + model + '-\\d{4}-\\d{2}-\\d{2}$').test(data.model));
  const bounded = typeof content === 'string' && Buffer.byteLength(content, 'utf8') <= 4096;
  // No credential is present in model input. Still suppress recognizable credential-shaped output.
  const sensitive = bounded && /sk-[A-Za-z0-9_-]{8,}|Bearer\s+\S+|-----BEGIN [A-Z ]*PRIVATE KEY-----|(?:api[_ -]?key|authorization)\s*[:=]/i.test(content);
  const finish = ['stop', 'length', 'content_filter', 'tool_calls', 'function_call'].includes(choice?.finish_reason) ? choice.finish_reason : 'unknown';
  const refusal = Boolean(choice?.message?.refusal);
  const valid = Boolean(matchingModel && usage && (model !== 'gpt-4o-mini' || usage.prompt_tokens <= 128000) &&
    data?.choices?.length === 1 && finish === 'stop' && !refusal && !choice.message.tool_calls && bounded && !sensitive && content.trim());
  return { caseId: item.caseId, model, requestSha256: item.sha256, transportValid: valid, quality: 'human-review-required',
    usage, finish, refusal, elapsedMs: Math.max(0, Math.round(elapsedMs)),
    reply: matchingModel && bounded && !sensitive ? content : null,
    replyStatus: sensitive ? 'redacted-sensitive-pattern' : bounded ? 'bounded-text' : 'invalid-or-oversize' };
}

function guardedFetch(fetchImpl) {
  let sends = 0;
  return async (url, init) => {
    if (String(url) !== ENDPOINT || init?.method !== 'POST' || sends >= 4 ||
        typeof init.body !== 'string' || Buffer.byteLength(init.body) > 20000) throw new Error('transport-blocked');
    // Exact semantic body match; SDK whitespace formatting is allowed.
    if (JSON.stringify(JSON.parse(init.body)) !== JSON.stringify(requestBody(sends))) throw new Error('body-blocked');
    sends += 1; // Count before sending: exceptions/timeouts never free a slot.
    const response = await fetchImpl(ENDPOINT, { ...init, redirect: 'error' });
    const reader = response.body?.getReader();
    if (!reader) throw new Error('missing-body');
    const chunks = [];
    let bytes = 0;
    try {
      while (true) {
        const chunk = await reader.read();
        if (chunk.done) break;
        bytes += chunk.value.byteLength;
        if (bytes > MAX_RESPONSE_BYTES) throw new Error('response-too-large');
        chunks.push(chunk.value);
      }
    } finally { await reader.cancel().catch(() => {}); }
    // Whitelist response headers; do not propagate arbitrary provider metadata.
    return new Response(Buffer.concat(chunks), { status: response.status,
      headers: { 'content-type': 'application/json' } });
  };
}

async function run({ execute = false, loadSDK, fetchImpl = globalThis.fetch, emit = () => {} } = {}) {
  if (!execute) { emit(plan()); return 0; }
  let client;
  try {
    const OpenAI = loadSDK();
    client = new OpenAI({ baseURL: 'https://api.openai.com/v1', maxRetries: 0, timeout: REQUEST_MS,
      fetch: guardedFetch(fetchImpl) }); // SDK alone reads the inherited credential.
  } catch { emit({ status: 'setup-failed', attempts: 0 }); return 1; }
  for (let index = 0; index < 4; index++) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), REQUEST_MS);
    const start = performance.now();
    try {
      const data = await client.chat.completions.create(requestBody(index), { signal: controller.signal, maxRetries: 0 });
      const result = evaluate(index, data, performance.now() - start);
      emit(result);
      if (!result.transportValid) return 1; // Human quality review remains separate.
    } catch {
      emit({ caseId: FROZEN.requests[index].caseId, model: FROZEN.requests[index].body.model,
        transportValid: false, quality: 'not-evaluated', status: 'request-failed-cost-unknown', elapsedMs: Math.round(performance.now() - start) });
      return 1;
    } finally { clearTimeout(timer); }
  }
  return 0;
}

async function main(args) {
  const emit = value => process.stdout.write(`${JSON.stringify(value)}\n`);
  const live = args.length === 3 && args[0] === '--execute' && args[1] === '--standard-pricing-reviewed-2026-10-15' && args[2] === '--prior-charge-and-overall-budget-reviewed';
  if (args.length && !(args.length === 1 && args[0] === '--dry-run') && !live) {
    emit({ status: 'invalid-arguments' }); return 2;
  }
  if (!live) return run({ emit });
  // Refuse ambient debugging/preloads; do not print their values. Shell launcher also removes them before Node starts.
  if (process.env.NODE_TLS_REJECT_UNAUTHORIZED === '0' ||
      process.env.DEBUG || process.env.NODE_DEBUG || process.env.NODE_DEBUG_NATIVE ||
      process.env.NODE_V8_COVERAGE || process.env.NODE_REDIRECT_WARNINGS ||
      process.env.NODE_OPTIONS || process.env.NODE_PATH || process.env.NODE_USE_ENV_PROXY ||
      !process.execArgv.includes('--max-old-space-size=64') || !process.execArgv.includes('--max-http-header-size=8192')) {
    emit({ status: 'unsafe-launch-options' }); return 2;
  }
  const deadline = setTimeout(() => { emit({ status: 'deadline-cost-unknown' }); process.exit(1); }, DEADLINE_MS);
  const memory = setInterval(() => {
    if (process.memoryUsage().rss > 128 * 1024 * 1024) { emit({ status: 'memory-limit-cost-unknown' }); process.exit(1); }
  }, 100);
  try {
    return await run({ execute: true, emit, loadSDK: () => {
      const { createRequire } = require('node:module');
      const { resolve } = require('node:path');
      // Resolve ONLY the already installed SDK from the Render backend working directory.
      const sdkRequire = createRequire(resolve(process.cwd(), 'synthetic-probe.cjs'));
      if (sdkRequire('openai/version').VERSION !== '4.104.0') throw new Error('unreviewed-sdk');
      return sdkRequire('openai');
    } });
  } finally { clearTimeout(deadline); clearInterval(memory); }
}

module.exports = { requestBody, costBound, plan, safeUsage, evaluate, guardedFetch, run, main };
if (require.main === module || (process.argv[1] === '-' && !module.parent)) main(process.argv.slice(2)).then(code => { process.exitCode = code; }).catch(() => {
  process.stdout.write('{"status":"internal-failure"}\n'); process.exitCode = 1;
});
