-- ═══════════════════════════════════════════════════════════════════════════
-- Family Food Assistant — DEVELOPMENT seed data (never run in production).
--
-- 1. Sign up in the app (or Dashboard → Authentication → Add user).
-- 2. Put that user's email below and run this file in the SQL Editor.
-- All rows are labelled "Demo" so they are easy to spot and delete.
-- ═══════════════════════════════════════════════════════════════════════════

do $$
declare
  v_email constant text := 'you@example.com';   -- ← CHANGE ME
  uid  uuid;
  plan uuid := gen_random_uuid();
  wk   date := date_trunc('week', current_date)::date;
begin
  select id into uid from auth.users where email = v_email;
  if uid is null then
    raise exception 'No auth user with email %. Sign up first, then edit v_email in seed.sql.', v_email;
  end if;

  update public.profiles
     set name = coalesce(nullif(name, ''), 'Demo Chef'), diet = 'eggetarian', spice_level = 2,
         food_preferences = '{North Indian,Quick meals}', favorite_foods = '{Paneer,Dal}',
         disliked_foods = '{Bitter gourd}', cooking_streak = 3, last_cooked_on = current_date - 1
   where id = uid;

  insert into public.ingredients (user_id, name, quantity, unit, category, purchase_date, expiry_date, notes) values
    (uid, 'Potato',       5,   'pieces', 'vegetables', current_date - 2, current_date + 12, 'Demo'),
    (uid, 'Tomato',       4,   'pieces', 'vegetables', current_date - 2, current_date + 2,  'Demo'),
    (uid, 'Onion',        3,   'pieces', 'vegetables', current_date - 2, current_date + 20, 'Demo'),
    (uid, 'Eggs',         8,   'pieces', 'eggs',       current_date - 1, current_date + 9,  'Demo'),
    (uid, 'Rice',         2,   'kg',     'grains',     current_date - 9, current_date + 180,'Demo'),
    (uid, 'Paneer',       200, 'g',      'dairy',      current_date - 1, current_date + 1,  'Demo'),
    (uid, 'Milk',         1,   'litre',  'dairy',      current_date,     current_date + 3,  'Demo'),
    (uid, 'Spinach',      1,   'packet', 'vegetables', current_date - 5, current_date - 1,  'Demo'),
    (uid, 'Green chilli', 6,   'pieces', 'vegetables', current_date - 2, current_date + 6,  'Demo'),
    (uid, 'Toor dal',     1,   'kg',     'grains',     current_date - 20, current_date + 200,'Demo');

  insert into public.shopping_list_items (user_id, name, quantity, category, priority, recipe_name) values
    (uid, 'Capsicum',         '2',       'vegetables', 1, 'Demo'),
    (uid, 'Coriander leaves', '1 bunch', 'vegetables', 2, 'Demo'),
    (uid, 'Curd',             '500 g',   'dairy',      1, 'Demo'),
    (uid, 'Wheat flour',      '5 kg',    'grains',     0, 'Demo');

  insert into public.meal_plans (id, user_id, week_start, people, budget, diet, meals_per_day)
    values (plan, uid, wk, 4, 2500, 'eggetarian', '{dinner}');
  insert into public.meal_plan_items (meal_plan_id, user_id, day_index, meal_type, recipe_name, emoji, description, ingredients, library_key) values
    (plan, uid, 0, 'dinner', 'Dal Tadka',              '🥣', 'Demo', '{toor dal,tomato,onion,garlic}', 'dal-tadka'),
    (plan, uid, 1, 'dinner', 'Aloo Paratha',           '🫓', 'Demo', '{wheat flour,potato,green chilli}', 'aloo-paratha'),
    (plan, uid, 2, 'dinner', 'Creamy Vegetable Pasta', '🍝', 'Demo', '{pasta,tomato,onion,capsicum,milk,cheese}', 'veg-pasta'),
    (plan, uid, 3, 'dinner', 'Egg Curry',              '🥚', 'Demo', '{egg,onion,tomato,ginger,garlic}', 'egg-curry'),
    (plan, uid, 4, 'dinner', 'Vegetable Pulao',        '🥕', 'Demo', '{rice,carrot,peas,beans,onion}', 'veg-pulao'),
    (plan, uid, 5, 'dinner', 'Rajma Chawal',           '🫘', 'Demo', '{rajma,onion,tomato,rice}', 'rajma-chawal'),
    (plan, uid, 6, 'dinner', 'Moong Dal Khichdi',      '🍲', 'Demo', '{rice,moong dal}', 'khichdi');

  raise notice 'Seeded demo data for %', v_email;
end $$;
