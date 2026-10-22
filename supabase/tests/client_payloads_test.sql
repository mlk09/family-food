-- Verifies every column the Flutter app writes exists and passes RLS,
-- mirroring the PostgREST upserts in lib/data/sync_engine.dart.
\set QUIET on
begin;
insert into auth.users (id, email) values ('44444444-4444-4444-8444-444444444444', 'app@test');
select set_config('request.jwt.claim.sub', '44444444-4444-4444-8444-444444444444', true);
set local role authenticated;

insert into public.ingredients (id, user_id, family_id, name, quantity, unit, category, purchase_date, expiry_date, notes, updated_at)
values (gen_random_uuid(), auth.uid(), null, 'Tomato', 4, 'pieces', 'vegetables', '2026-10-20', '2026-10-24', null, now())
on conflict (id) do update set quantity = excluded.quantity;

insert into public.shopping_list_items (id, user_id, family_id, list_id, name, quantity, category, priority, checked, recipe_name, updated_at)
values (gen_random_uuid(), auth.uid(), null, null, 'Paneer', '200 g', 'dairy', 2, false, 'Palak Paneer', now());

insert into public.meal_plans (id, user_id, family_id, week_start, people, budget, diet, meals_per_day, updated_at)
values ('55555555-5555-4555-8555-555555555555', auth.uid(), null, '2026-10-19', 4, 2500, 'vegetarian', '{breakfast,dinner}', now());
insert into public.meal_plan_items (id, meal_plan_id, user_id, family_id, day_index, meal_type, recipe_name, emoji, description, ingredients, library_key)
values (gen_random_uuid(), '55555555-5555-4555-8555-555555555555', auth.uid(), null, 0, 'dinner', 'Dal Tadka', '🥣', '', '{toor dal,tomato}', 'dal-tadka');

insert into public.recipes (id, user_id, family_id, name, source, data)
values ('66666666-6666-4666-8666-666666666666', auth.uid(), null, 'Egg Fried Rice', 'library', '{"name":"Egg Fried Rice"}')
on conflict (id) do update set data = excluded.data;
insert into public.saved_recipes (id, user_id, family_id, recipe_id)
values (gen_random_uuid(), auth.uid(), null, '66666666-6666-4666-8666-666666666666')
on conflict (user_id, recipe_id) do nothing;
select r.data->>'name' from public.saved_recipes s join public.recipes r on r.id = s.recipe_id;  -- recipes(data) embed

update public.profiles set name = 'App', avatar_url = null, age_group = 'child', diet = 'jain',
  food_preferences = '{}', allergies = '{peanuts}', favorite_foods = '{}', disliked_foods = '{}',
  spice_level = 1, cooking_streak = 2, last_cooked_on = current_date
where id = auth.uid();

insert into public.user_preferences (user_id, notify_expiry, notify_meals, notify_shopping, notify_plan, updated_at)
values (auth.uid(), true, true, false, false, now())
on conflict (user_id) do update set notify_meals = excluded.notify_meals;

insert into public.ai_conversations (id, user_id, title) values ('77777777-7777-4777-8777-777777777777', auth.uid(), 'Hi');
insert into public.ai_messages (id, conversation_id, user_id, role, content)
values (gen_random_uuid(), '77777777-7777-4777-8777-777777777777', auth.uid(), 'user', 'What can I cook?');

delete from public.saved_recipes where recipe_id = '66666666-6666-4666-8666-666666666666';
delete from public.meal_plan_items where meal_plan_id = '55555555-5555-4555-8555-555555555555';
rollback;
\echo 'CLIENT PAYLOAD TEST PASSED'
