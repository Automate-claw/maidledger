-- ============================================================
-- Migration: subcategories + weight_options
-- 目的：物價平台完整粒度
-- ============================================================

-- ─── Subcategories ───
-- prd_categories 細分，用於 weight_options、分析維度

CREATE TABLE IF NOT EXISTS subcategories (
  id SERIAL PRIMARY KEY,
  code TEXT UNIQUE NOT NULL,
  name_tc TEXT NOT NULL,
  name_en TEXT,
  parent_cate TEXT REFERENCES prd_categories(code),  -- e.g. 'fish' → 屬於魚類
  display_order INT DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_subcategories_parent ON subcategories(parent_cate);

-- ─── Weight Options ───
-- 每個 subcategory 對應嘅 weight list

CREATE TABLE IF NOT EXISTS weight_options (
  id SERIAL PRIMARY KEY,
  subcategory_code TEXT NOT NULL REFERENCES subcategories(code),
  weight_g INTEGER NOT NULL,        -- 170, 500, 604, 6...
  label TEXT NOT NULL,              -- '170g', '1斤 (605g)', '6粒'
  unit_type TEXT DEFAULT 'g' CHECK (unit_type IN ('g', 'pcs', 'kg')),  -- g=克, pcs=件, kg=公斤
  display_order INT DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_weight_options_subcategory ON weight_options(subcategory_code);

-- ─── Seed: subcategories ───
INSERT INTO subcategories (code, name_tc, name_en, parent_cate, display_order) VALUES
  -- Fish
  ('fresh_fish', '新鮮魚', 'Fresh Fish', 'fish', 1),
  ('fish_fillet', '魚柳/魚片', 'Fish Fillet', 'fish', 2),
  ('fish_ball', '魚肉丸/魚蛋', 'Fish Ball/Egg', 'fish', 3),
  ('dried_fish', '鹹魚/乾魚', 'Dried Fish', 'fish', 4),
  ('fish_tofu', '魚豆腐', 'Fish Tofu', 'fish', 5),
  -- Pork
  ('pork_belly', '豬腩/五花腩', 'Pork Belly', 'pork', 1),
  ('pork_loin', '豬柳/瘦肉', 'Pork Loin', 'pork', 2),
  ('pork_trotter', '豬手/豬腳', 'Pork Trotter', 'pork', 3),
  ('pork_offal', '豬內臟', 'Pork Offal', 'pork', 4),
  -- Beef
  ('beef_fillet', '牛柳/牛肉片', 'Beef Fillet', 'beef', 1),
  ('beef_shin', '牛腩/牛展', 'Beef Shin', 'beef', 2),
  ('beef_offal', '牛內臟', 'Beef Offal', 'beef', 3),
  -- Chicken
  ('chicken_whole', '全雞/雞髀', 'Whole Chicken/Leg', 'chicken', 1),
  ('chicken_breast', '雞柳/雞胸', 'Chicken Fillet', 'chicken', 2),
  ('chicken_offal', '雞內臟', 'Chicken Offal', 'chicken', 3),
  -- Vegetables
  ('veg_leafy', '葉菜', 'Leafy Vegetables', 'vegetables', 1),
  ('veg_root', '根莖菜', 'Root Vegetables', 'vegetables', 2),
  ('veg_fruit', '瓜果類', 'Fruit Vegetables', 'vegetables', 3),
  ('veg_mushroom', '菇類', 'Mushrooms', 'vegetables', 4),
  ('veg_bean', '豆類', 'Beans/Legumes', 'vegetables', 5),
  -- Rice/Grains
  ('rice', '米', 'Rice', 'rice', 1),
  ('noodle', '麵', 'Noodles', 'rice', 2),
  ('flour', '麵粉/糯米粉', 'Flour', 'rice', 3),
  -- Oil
  ('oil_cooking', '煮食油', 'Cooking Oil', 'oil', 1),
  ('oil_special', '特色油/香料油', 'Specialty Oil', 'oil', 2),
  -- Seasoning
  ('season_sauces', '醬料', 'Sauces', 'seasoning', 1),
  ('season_herbs', '香料/草本', 'Herbs/Spices', 'seasoning', 2),
  ('season_stock', '湯底/高湯', 'Stock', 'seasoning', 3),
  -- Snack
  ('snack_sweet', '甜品零食', 'Sweet Snacks', 'snack', 1),
  ('snack_salty', '鹹味零食', 'Salty Snacks', 'snack', 2),
  ('snack_nuts', '堅果/果仁', 'Nuts', 'snack', 3),
  -- Drink
  ('drink_soft', '汽水/軟飲', 'Soft Drinks', 'drink', 1),
  ('drink_tea', '茶/茶包', 'Tea', 'drink', 2),
  ('drink_juice', '果汁', 'Juice', 'drink', 3),
  ('drink_milk', '奶類', 'Milk', 'drink', 4),
  -- Daily
  ('daily_cleaning', '清潔用品', 'Cleaning', 'daily', 1),
  ('daily_paper', '紙品', 'Paper Products', 'daily', 2),
  ('daily_personal', '個人護理', 'Personal Care', 'daily', 3),
  ('daily_kitchen', '廚房用品', 'Kitchen', 'daily', 4),
  ('daily_other', '其他日用品', 'Others', 'daily', 5)
ON CONFLICT (code) DO NOTHING;

-- ─── Seed: weight_options ───
INSERT INTO weight_options (subcategory_code, weight_g, label, unit_type, display_order) VALUES
  -- fresh_fish
  ('fresh_fish', 500, '500g', 'g', 1),
  ('fresh_fish', 604, '1斤 (605g)', 'g', 2),
  ('fresh_fish', 700, '1.15斤 (700g)', 'g', 3),
  ('fresh_fish', 800, '1.3斤 (800g)', 'g', 4),
  ('fresh_fish', 1000, '1kg', 'g', 5),
  ('fresh_fish', 1210, '2斤', 'g', 6),
  -- fish_fillet
  ('fish_fillet', 150, '150g', 'g', 1),
  ('fish_fillet', 250, '250g', 'g', 2),
  ('fish_fillet', 300, '300g', 'g', 3),
  ('fish_fillet', 400, '400g', 'g', 4),
  ('fish_fillet', 500, '500g', 'g', 5),
  -- fish_ball
  ('fish_ball', 170, '170g', 'g', 1),
  ('fish_ball', 250, '250g', 'g', 2),
  ('fish_ball', 300, '300g', 'g', 3),
  ('fish_ball', 500, '500g', 'g', 4),
  ('fish_ball', 6, '6粒', 'pcs', 5),
  ('fish_ball', 12, '12粒', 'pcs', 6),
  ('fish_ball', 20, '20粒', 'pcs', 7),
  -- eggs (隻)
  ('fish_ball', 6, '6隻', 'pcs', 8),
  ('fish_ball', 10, '10隻', 'pcs', 9),
  ('fish_ball', 12, '12隻', 'pcs', 10),
  ('fish_ball', 30, '30隻', 'pcs', 11),
  -- pork_belly
  ('pork_belly', 300, '300g', 'g', 1),
  ('pork_belly', 500, '500g', 'g', 2),
  ('pork_belly', 604, '1斤 (605g)', 'g', 3),
  ('pork_belly', 800, '1.3斤 (800g)', 'g', 4),
  ('pork_belly', 1000, '1kg', 'g', 5),
  -- pork_loin
  ('pork_loin', 300, '300g', 'g', 1),
  ('pork_loin', 500, '500g', 'g', 2),
  ('pork_loin', 604, '1斤 (605g)', 'g', 3),
  ('pork_loin', 1000, '1kg', 'g', 4),
  -- beef_fillet
  ('beef_fillet', 150, '150g', 'g', 1),
  ('beef_fillet', 250, '250g', 'g', 2),
  ('beef_fillet', 300, '300g', 'g', 3),
  ('beef_fillet', 500, '500g', 'g', 4),
  -- chicken_whole
  ('chicken_whole', 500, '500g', 'g', 1),
  ('chicken_whole', 800, '800g', 'g', 2),
  ('chicken_whole', 1000, '1kg', 'g', 3),
  ('chicken_whole', 1200, '1.2kg', 'g', 4),
  ('chicken_whole', 1500, '1.5kg', 'g', 5),
  ('chicken_whole', 1800, '1.8kg', 'g', 6),
  -- veg_leafy
  ('veg_leafy', 300, '300g', 'g', 1),
  ('veg_leafy', 500, '500g', 'g', 2),
  ('veg_leafy', 604, '1斤 (605g)', 'g', 3),
  -- veg_root
  ('veg_root', 300, '300g', 'g', 1),
  ('veg_root', 500, '500g', 'g', 2),
  ('veg_root', 1000, '1kg', 'g', 3),
  -- veg_fruit
  ('veg_fruit', 300, '300g', 'g', 1),
  ('veg_fruit', 500, '500g', 'g', 2),
  ('veg_fruit', 1000, '1kg', 'g', 3),
  -- rice
  ('rice', 1000, '1kg', 'g', 1),
  ('rice', 2000, '2kg', 'g', 2),
  ('rice', 5000, '5kg', 'g', 3),
  ('rice', 10000, '10kg', 'g', 4),
  -- oil_cooking
  ('oil_cooking', 500, '500ml', 'g', 1),
  ('oil_cooking', 1000, '1L', 'g', 2),
  ('oil_cooking', 2000, '2L', 'g', 3),
  ('oil_cooking', 4000, '4L', 'g', 4),
  -- daily_cleaning
  ('daily_cleaning', 500, '500g', 'g', 1),
  ('daily_cleaning', 750, '750g', 'g', 2),
  ('daily_cleaning', 1000, '1kg', 'g', 3),
  -- daily_paper
  ('daily_paper', 10, '10卷', 'pcs', 1),
  ('daily_paper', 20, '20卷', 'pcs', 2),
  ('daily_paper', 30, '30卷', 'pcs', 3)
ON CONFLICT DO NOTHING;

-- ─── receipt_items 新增 subcategory_code ───
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'receipt_items' AND column_name = 'subcategory_code'
  ) THEN
    ALTER TABLE receipt_items ADD COLUMN subcategory_code TEXT REFERENCES subcategories(code);
  END IF;
END
$$;
