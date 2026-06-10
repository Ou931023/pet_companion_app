-- CR-0066+ 商城（marketplace）JSON → PostgreSQL 平移：型別放寬 + 種子商品。
--
-- 背景：009 建表時 id 用 UUID DEFAULT gen_random_uuid()，但 store 對外用固定字串
-- id（種子 seed-*，CR-0032；訂單用 randomUUID()）。為了讓 DB 與 store 的字串 id
-- 契約一致，這份 migration 把 marketplace_products / marketplace_orders 的 id 放寬為 TEXT。
--
-- 冪等性（migrate.js 每次部署都 glob 重跑所有 *.sql）：
--   - ALTER COLUMN id DROP DEFAULT：已無 default 時為 no-op、不報錯。
--   - ALTER COLUMN id TYPE TEXT：已是 TEXT 時等同重寫、不報錯（對全新（009 UUID）
--     與已套用本檔（TEXT）的 DB 皆安全可重跑）。
--   - 種子 INSERT ... ON CONFLICT (id) DO NOTHING：已存在不覆蓋、可重跑。
-- 本檔不含任何破壞性操作（無 DROP COLUMN / DROP TABLE / TRUNCATE）。

-- 1) id 型別放寬為 TEXT（products / orders）。
ALTER TABLE marketplace_products ALTER COLUMN id DROP DEFAULT;
ALTER TABLE marketplace_products ALTER COLUMN id TYPE TEXT;

ALTER TABLE marketplace_orders ALTER COLUMN id DROP DEFAULT;
ALTER TABLE marketplace_orders ALTER COLUMN id TYPE TEXT;

-- 2) 灌入 15 筆 Demo 種子商品（與 marketplaceStore.js 的 SEED_PRODUCTS 一致）。
--    image_url 一律空字串（長者端自畫分類色卡 placeholder，正式照片於後台改 URL）。
--    固定字串 id（seed-*）；ON CONFLICT 不覆蓋既有資料。
INSERT INTO marketplace_products
  (id, center_id, center_name, name, description, category, price, stock, image_url, status, commission_rate, created_at, updated_at)
VALUES
  ('seed-bath-chair', 'center-anxin', '安心長照中心', '防滑沐浴椅', '洗澡時穩穩坐著，椅腳防滑，幫長輩洗得安心又安全。', '照護用品', 1800, 12, '', 'active', 0.100, NOW(), NOW()),
  ('seed-care-bed', 'center-anxin', '安心長照中心', '居家電動照護床', '可調高低和角度，起身、翻身都省力，照顧者腰背也輕鬆。', '照護用品', 18800, 4, '', 'active', 0.100, NOW(), NOW()),
  ('seed-walker', 'center-anxin', '安心長照中心', '助行器', '輕巧好推、握把好抓，外出散步多一份支撐和安全感。', '復健輔具', 2500, 6, '', 'active', 0.100, NOW(), NOW()),
  ('seed-wheelchair', 'center-anxin', '安心長照中心', '輕量摺疊輪椅', '車身輕、好收折，進出車子或外出看診都方便。', '復健輔具', 4200, 5, '', 'active', 0.100, NOW(), NOW()),
  ('seed-cane', 'center-anxin', '安心長照中心', '四腳止滑拐杖', '四個腳穩穩站，站立走路更安心，握把好握不咬手。', '復健輔具', 680, 20, '', 'active', 0.100, NOW(), NOW()),
  ('seed-anti-slip-slippers', 'center-anxin', '安心長照中心', '防滑居家拖鞋', '鞋底止滑、包覆好穿脫，在家走動更安全，減少跌倒。', '日常生活', 450, 25, '', 'active', 0.100, NOW(), NOW()),
  ('seed-bp-monitor', 'center-anxin', '安心長照中心', '電子血壓計', '一鍵量測、大字幕好讀，在家就能天天記錄血壓變化。', '其他', 1280, 15, '', 'active', 0.100, NOW(), NOW()),
  ('seed-protein-drink', 'center-kangfu', '康福長照中心', '高蛋白營養飲', '胃口不好也能補充營養，順口好喝，幫長輩維持體力。', '營養補充', 899, 20, '', 'active', 0.120, NOW(), NOW()),
  ('seed-milk-powder', 'center-kangfu', '康福長照中心', '銀髮營養奶粉', '好沖泡好吸收，補充每天需要的營養，照顧腸胃也照顧體力。', '營養補充', 1150, 18, '', 'active', 0.120, NOW(), NOW()),
  ('seed-vitamins', 'center-kangfu', '康福長照中心', '綜合維他命保健', '一天一顆，補足日常容易缺的維他命，幫長輩維持精神。', '營養補充', 650, 30, '', 'active', 0.120, NOW(), NOW()),
  ('seed-adult-diaper', 'center-kangfu', '康福長照中心', '成人紙尿褲', '透氣不悶、吸收力好，日常照護更輕鬆，長輩也舒服。', '清潔衛生', 650, 30, '', 'active', 0.120, NOW(), NOW()),
  ('seed-wet-wipes', 'center-kangfu', '康福長照中心', '濕式衛生紙巾', '溫和不刺激，擦拭清潔很方便，外出或臥床照護都好用。', '清潔衛生', 120, 50, '', 'active', 0.120, NOW(), NOW()),
  ('seed-care-pad', 'center-kangfu', '康福長照中心', '看護墊', '吸收力強、表面乾爽，鋪床或座椅都能用，換洗更省事。', '清潔衛生', 380, 40, '', 'active', 0.120, NOW(), NOW()),
  ('seed-food-container', 'center-kangfu', '康福長照中心', '保溫餐盒', '保溫保鮮，讓長輩好好吃上一頓熱飯，外出送餐也方便。', '日常生活', 560, 22, '', 'active', 0.120, NOW(), NOW()),
  ('seed-thermometer', 'center-kangfu', '康福長照中心', '電子體溫計', '幾秒就量好、嗶聲提醒，量體溫不費力，數字看得清楚。', '其他', 480, 28, '', 'active', 0.120, NOW(), NOW())
ON CONFLICT (id) DO NOTHING;
