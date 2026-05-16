CREATE TABLE IF NOT EXISTS prd_categories (
  id SERIAL PRIMARY KEY,
  code TEXT UNIQUE NOT NULL,
  name_tc TEXT NOT NULL,
  name_en TEXT,
  description TEXT,
  display_order INT DEFAULT 0
);

CREATE TABLE IF NOT EXISTS store_categories (
  id SERIAL PRIMARY KEY,
  code TEXT UNIQUE NOT NULL,
  name_tc TEXT NOT NULL,
  name_en TEXT,
  description TEXT,
  display_order INT DEFAULT 0
);

INSERT INTO prd_categories (code, name_tc, name_en, display_order) VALUES
  ('fish', '魚/海鮮', 'Fish/Seafood', 1),
  ('pork', '豬肉', 'Pork', 2),
  ('beef', '牛肉', 'Beef', 3),
  ('chicken', '雞肉', 'Chicken', 4),
  ('vegetables', '蔬菜', 'Vegetables', 5),
  ('rice', '米/穀物', 'Rice/Grains', 6),
  ('oil', '油', 'Cooking Oil', 7),
  ('seasoning', '調味', 'Seasoning', 8),
  ('snack', '零食', 'Snacks', 9),
  ('drink', '飲料', 'Drinks', 10),
  ('daily', '日用品', 'Daily Necessities', 11),
  ('other', '其他', 'Other', 12)
ON CONFLICT (code) DO NOTHING;

INSERT INTO store_categories (code, name_tc, name_en, display_order) VALUES
  ('supermarket', '超市', 'Supermarket', 1),
  ('wet_market', '街市', 'Wet Market', 2),
  ('pharmacy', '藥房', 'Pharmacy', 3),
  ('convenience', '便利店', 'Convenience Store', 4),
  ('online', '網購', 'Online Shopping', 5),
  ('restaurant', '餐廳', 'Restaurant', 6),
  ('cafe', '茶餐廳/咖啡店', 'Cafe', 7),
  ('other', '其他', 'Other', 99)
ON CONFLICT (code) DO NOTHING;