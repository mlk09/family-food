-- ═══════════════════════════════════════════════════════════════════════════
-- Family Food Assistant — Supabase schema, Row Level Security & RPCs
-- Run in Supabase Dashboard → SQL Editor (or `supabase db push`).
-- Safe to re-run: uses IF NOT EXISTS / OR REPLACE / DROP POLICY IF EXISTS.
-- ═══════════════════════════════════════════════════════════════════════════

create extension if not exists pgcrypto;

-- ───────────────────────── Helpers ─────────────────────────

create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

-- Rows keep their original owner even when a family member edits them.
create or replace function public.keep_owner()
returns trigger language plpgsql as $$
begin
  new.user_id := old.user_id;
  return new;
end $$;

-- Readable invite codes (no 0/O/1/I to avoid confusion).
create or replace function public.gen_invite_code()
returns text language plpgsql as $$
declare
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  code text;
begin
  loop
    code := '';
    for i in 1..6 loop
      code := code || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
    end loop;
    exit when not exists (select 1 from public.families f where f.invite_code = code);
  end loop;
  return code;
end $$;

-- ───────────────────────── Families ─────────────────────────

create table if not exists public.families (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (char_length(name) between 1 and 60),
  invite_code text not null unique,
  created_by  uuid references auth.users(id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create table if not exists public.family_members (
  id           uuid primary key default gen_random_uuid(),
  family_id    uuid not null references public.families(id) on delete cascade,
  user_id      uuid not null references auth.users(id) on delete cascade,
  display_name text not null default 'Member' check (char_length(display_name) between 1 and 40),
  role         text not null default 'member' check (role in ('dad','mom','child','grandma','grandpa','member')),
  is_admin     boolean not null default false,
  created_at   timestamptz not null default now(),
  unique (user_id)               -- one family per user keeps sharing simple
);
create index if not exists family_members_family_idx on public.family_members(family_id);

-- SECURITY DEFINER avoids RLS recursion when policies check membership.
create or replace function public.is_family_member(fid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.family_members m where m.family_id = fid and m.user_id = auth.uid());
$$;

-- ───────────────────────── Profiles & preferences ─────────────────────────

create table if not exists public.profiles (
  id               uuid primary key references auth.users(id) on delete cascade,
  user_id          uuid generated always as (id) stored,
  name             text not null default '' check (char_length(name) <= 60),
  avatar_url       text,
  age_group        text not null default 'adult' check (age_group in ('child','teen','adult','senior')),
  diet             text not null default 'vegetarian' check (diet in ('vegetarian','vegan','eggetarian','non-vegetarian','jain','other')),
  food_preferences text[] not null default '{}',
  allergies        text[] not null default '{}',
  favorite_foods   text[] not null default '{}',
  disliked_foods   text[] not null default '{}',
  spice_level      smallint not null default 2 check (spice_level between 0 and 4),
  family_id        uuid references public.families(id) on delete set null,
  cooking_streak   integer not null default 0 check (cooking_streak >= 0),
  last_cooked_on   date,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create index if not exists profiles_family_idx on public.profiles(family_id);

create table if not exists public.user_preferences (
  user_id         uuid primary key references auth.users(id) on delete cascade,
  theme_mode      text not null default 'dark' check (theme_mode in ('system','light','dark')),
  notify_expiry   boolean not null default true,
  notify_meals    boolean not null default false,
  notify_shopping boolean not null default false,
  notify_plan     boolean not null default false,
  breakfast_hour  smallint not null default 8 check (breakfast_hour between 0 and 23),
  lunch_hour      smallint not null default 13 check (lunch_hour between 0 and 23),
  dinner_hour     smallint not null default 20 check (dinner_hour between 0 and 23),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

-- ───────────────────────── Kitchen ─────────────────────────

create table if not exists public.ingredient_categories (
  id         text primary key,
  label      text not null,
  emoji      text not null,
  sort_order smallint not null default 0
);

insert into public.ingredient_categories (id, label, emoji, sort_order) values
  ('vegetables','Vegetables','🥕',1), ('fruits','Fruits','🍎',2), ('dairy','Dairy','🥛',3),
  ('meat','Meat','🍗',4), ('eggs','Eggs','🥚',5), ('grains','Grains','🌾',6),
  ('spices','Spices','🌶️',7), ('snacks','Snacks','🍪',8), ('frozen','Frozen','🧊',9), ('other','Other','🧺',10)
on conflict (id) do nothing;

create table if not exists public.ingredients (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null default auth.uid() references auth.users(id) on delete cascade,
  family_id     uuid references public.families(id) on delete set null,
  name          text not null check (char_length(name) between 1 and 60),
  quantity      numeric(12,2) not null default 1 check (quantity > 0),
  unit          text not null default 'pieces' check (unit in ('kg','g','litre','ml','pieces','packet','bottle','cup','spoon')),
  category      text not null default 'other' references public.ingredient_categories(id),
  purchase_date date,
  expiry_date   date,
  notes         text check (char_length(notes) <= 300),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index if not exists ingredients_user_idx on public.ingredients(user_id);
create index if not exists ingredients_family_idx on public.ingredients(family_id);
create index if not exists ingredients_expiry_idx on public.ingredients(expiry_date);

-- ───────────────────────── Recipes ─────────────────────────

create table if not exists public.recipes (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null default auth.uid() references auth.users(id) on delete cascade,
  family_id  uuid references public.families(id) on delete set null,
  name       text not null check (char_length(name) between 1 and 80),
  source     text not null default 'ai' check (source in ('ai','library','demo','user')),
  data       jsonb not null,           -- full validated recipe (ingredients, steps, nutrition…)
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists recipes_user_idx on public.recipes(user_id);
create index if not exists recipes_family_idx on public.recipes(family_id);

create table if not exists public.saved_recipes (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null default auth.uid() references auth.users(id) on delete cascade,
  family_id  uuid references public.families(id) on delete set null,
  recipe_id  uuid not null references public.recipes(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (user_id, recipe_id)
);
create index if not exists saved_recipes_family_idx on public.saved_recipes(family_id);
create index if not exists saved_recipes_recipe_idx on public.saved_recipes(recipe_id);

-- ───────────────────────── Meal plans ─────────────────────────

create table if not exists public.meal_plans (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null default auth.uid() references auth.users(id) on delete cascade,
  family_id     uuid references public.families(id) on delete set null,
  week_start    date not null,
  people        smallint not null default 4 check (people between 1 and 50),
  budget        integer check (budget is null or budget >= 0),
  diet          text not null default 'vegetarian',
  meals_per_day text[] not null default '{dinner}',
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index if not exists meal_plans_user_idx on public.meal_plans(user_id);
create index if not exists meal_plans_family_idx on public.meal_plans(family_id, updated_at desc);

create table if not exists public.meal_plan_items (
  id           uuid primary key default gen_random_uuid(),
  meal_plan_id uuid not null references public.meal_plans(id) on delete cascade,
  user_id      uuid not null default auth.uid() references auth.users(id) on delete cascade,
  family_id    uuid references public.families(id) on delete set null,
  day_index    smallint not null check (day_index between 0 and 6),
  meal_type    text not null check (meal_type in ('breakfast','lunch','dinner','snack')),
  recipe_name  text not null check (char_length(recipe_name) between 1 and 80),
  emoji        text not null default '🍽️',
  description  text not null default '',
  ingredients  text[] not null default '{}',
  library_key  text,                     -- built-in recipe slug, when applicable
  created_at   timestamptz not null default now()
);
create index if not exists meal_plan_items_plan_idx on public.meal_plan_items(meal_plan_id);
create index if not exists meal_plan_items_family_idx on public.meal_plan_items(family_id);

-- ───────────────────────── Shopping ─────────────────────────

create table if not exists public.shopping_lists (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null default auth.uid() references auth.users(id) on delete cascade,
  family_id  uuid references public.families(id) on delete set null,
  name       text not null default 'Shopping list',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists shopping_lists_user_idx on public.shopping_lists(user_id);
create index if not exists shopping_lists_family_idx on public.shopping_lists(family_id);

create table if not exists public.shopping_list_items (
  id          uuid primary key default gen_random_uuid(),
  list_id     uuid references public.shopping_lists(id) on delete cascade, -- filled by trigger
  user_id     uuid not null default auth.uid() references auth.users(id) on delete cascade,
  family_id   uuid references public.families(id) on delete set null,
  name        text not null check (char_length(name) between 1 and 60),
  quantity    text not null default '' check (char_length(quantity) <= 40),
  category    text not null default 'other',
  priority    smallint not null default 1 check (priority between 0 and 2),
  checked     boolean not null default false,
  recipe_name text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists shopping_items_list_idx on public.shopping_list_items(list_id);
create index if not exists shopping_items_user_idx on public.shopping_list_items(user_id);
create index if not exists shopping_items_family_idx on public.shopping_list_items(family_id);

-- Puts new items on the family list (or the user's personal list), creating it if needed.
create or replace function public.assign_shopping_list()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.list_id is null then
    if new.family_id is not null then
      select id into new.list_id from public.shopping_lists where family_id = new.family_id order by created_at limit 1;
    else
      select id into new.list_id from public.shopping_lists
        where user_id = new.user_id and family_id is null order by created_at limit 1;
    end if;
    if new.list_id is null then
      insert into public.shopping_lists (user_id, family_id) values (new.user_id, new.family_id) returning id into new.list_id;
    end if;
  end if;
  return new;
end $$;

-- ───────────────────────── Chef AI ─────────────────────────

create table if not exists public.ai_conversations (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null default auth.uid() references auth.users(id) on delete cascade,
  title      text not null default 'Chat' check (char_length(title) <= 80),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists ai_conversations_user_idx on public.ai_conversations(user_id, updated_at desc);

create table if not exists public.ai_messages (
  id              uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.ai_conversations(id) on delete cascade,
  user_id         uuid not null default auth.uid() references auth.users(id) on delete cascade,
  role            text not null check (role in ('user','assistant')),
  content         text not null check (char_length(content) <= 20000),
  created_at      timestamptz not null default now()
);
create index if not exists ai_messages_conv_idx on public.ai_messages(conversation_id, created_at);
create index if not exists ai_messages_user_idx on public.ai_messages(user_id);

-- Per-user daily AI request counter (written only by the Edge Function).
create table if not exists public.ai_usage (
  user_id uuid not null references auth.users(id) on delete cascade,
  day     date not null default current_date,
  count   integer not null default 0,
  primary key (user_id, day)
);

create or replace function public.increment_ai_usage(p_user uuid, p_limit integer)
returns boolean language plpgsql security definer set search_path = public as $$
declare n integer;
begin
  insert into public.ai_usage (user_id, day, count) values (p_user, current_date, 1)
  on conflict (user_id, day) do update set count = public.ai_usage.count + 1
  returning count into n;
  return n <= p_limit;
end $$;
revoke all on function public.increment_ai_usage(uuid, integer) from public, anon, authenticated;

-- ───────────────────────── Triggers ─────────────────────────

do $$
declare t text;
begin
  foreach t in array array['families','profiles','user_preferences','ingredients','recipes','meal_plans',
                           'shopping_lists','shopping_list_items','ai_conversations']
  loop
    execute format('drop trigger if exists trg_%1$s_updated on public.%1$s', t);
    execute format('create trigger trg_%1$s_updated before update on public.%1$s
                    for each row execute function public.set_updated_at()', t);
  end loop;
  foreach t in array array['ingredients','recipes','saved_recipes','meal_plans','meal_plan_items',
                           'shopping_lists','shopping_list_items','ai_conversations','ai_messages']
  loop
    execute format('drop trigger if exists trg_%1$s_owner on public.%1$s', t);
    execute format('create trigger trg_%1$s_owner before update on public.%1$s
                    for each row execute function public.keep_owner()', t);
  end loop;
end $$;

drop trigger if exists trg_shopping_assign_list on public.shopping_list_items;
create trigger trg_shopping_assign_list before insert or update on public.shopping_list_items
  for each row execute function public.assign_shopping_list();

-- New auth user → profile + preferences.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, name)
    values (new.id, left(coalesce(new.raw_user_meta_data->>'name', new.raw_user_meta_data->>'full_name', ''), 60))
    on conflict (id) do nothing;
  insert into public.user_preferences (user_id) values (new.id) on conflict (user_id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- ───────────────────────── Family RPCs ─────────────────────────

-- Moves the caller's own rows into (or out of) a family so they become shared.
create or replace function public._move_user_rows(p_user uuid, p_family uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_list uuid;
begin
  update public.ingredients     set family_id = p_family where user_id = p_user;
  update public.recipes         set family_id = p_family where user_id = p_user;
  update public.saved_recipes   set family_id = p_family where user_id = p_user;
  update public.meal_plans      set family_id = p_family where user_id = p_user;
  update public.meal_plan_items set family_id = p_family where user_id = p_user;

  if p_family is not null then
    select id into v_list from public.shopping_lists where family_id = p_family order by created_at limit 1;
    if v_list is null then
      update public.shopping_lists set family_id = p_family
        where id = (select id from public.shopping_lists where user_id = p_user and family_id is null order by created_at limit 1)
        returning id into v_list;
    end if;
    if v_list is null then
      insert into public.shopping_lists (user_id, family_id) values (p_user, p_family) returning id into v_list;
    end if;
    update public.shopping_list_items set family_id = p_family, list_id = v_list where user_id = p_user;
    delete from public.shopping_lists l
      where l.user_id = p_user and l.family_id is null
        and not exists (select 1 from public.shopping_list_items i where i.list_id = l.id);
  else
    update public.shopping_list_items set family_id = null, list_id = null where user_id = p_user; -- trigger re-assigns
  end if;
end $$;
revoke all on function public._move_user_rows(uuid, uuid) from public, anon, authenticated;

create or replace function public.create_family(p_name text, p_display_name text default 'Member', p_role text default 'member')
returns public.families language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  fam public.families;
begin
  if uid is null then raise exception 'not_authenticated'; end if;
  if exists (select 1 from public.family_members where user_id = uid) then raise exception 'already_in_family'; end if;
  if coalesce(trim(p_name), '') = '' then raise exception 'name_required'; end if;

  insert into public.families (name, invite_code, created_by)
    values (left(trim(p_name), 60), public.gen_invite_code(), uid) returning * into fam;
  insert into public.family_members (family_id, user_id, display_name, role, is_admin)
    values (fam.id, uid, left(coalesce(nullif(trim(p_display_name), ''), 'Member'), 40),
            case when p_role in ('dad','mom','child','grandma','grandpa') then p_role else 'member' end, true);
  update public.profiles set family_id = fam.id where id = uid;
  perform public._move_user_rows(uid, fam.id);
  return fam;
end $$;

create or replace function public.join_family(p_code text, p_display_name text default 'Member', p_role text default 'member')
returns public.families language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  fam public.families;
begin
  if uid is null then raise exception 'not_authenticated'; end if;
  if exists (select 1 from public.family_members where user_id = uid) then raise exception 'already_in_family'; end if;
  select * into fam from public.families where invite_code = upper(trim(p_code));
  if fam.id is null then raise exception 'invalid_code'; end if;

  insert into public.family_members (family_id, user_id, display_name, role)
    values (fam.id, uid, left(coalesce(nullif(trim(p_display_name), ''), 'Member'), 40),
            case when p_role in ('dad','mom','child','grandma','grandpa') then p_role else 'member' end);
  update public.profiles set family_id = fam.id where id = uid;
  perform public._move_user_rows(uid, fam.id);
  return fam;
end $$;

-- Core leave logic, reusable by the delete-account Edge Function (service role).
create or replace function public.leave_family_for(p_user uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  fid uuid;
  was_admin boolean;
begin
  select family_id, is_admin into fid, was_admin from public.family_members where user_id = p_user;
  if fid is null then return; end if;
  delete from public.family_members where user_id = p_user;
  update public.profiles set family_id = null where id = p_user;
  perform public._move_user_rows(p_user, null);   -- your own items go with you
  if not exists (select 1 from public.family_members where family_id = fid) then
    delete from public.families where id = fid;
  elsif was_admin then
    update public.family_members set is_admin = true
      where id = (select id from public.family_members where family_id = fid order by created_at limit 1);
  end if;
end $$;
revoke all on function public.leave_family_for(uuid) from public, anon, authenticated;
grant execute on function public.leave_family_for(uuid) to service_role;

create or replace function public.leave_family()
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  perform public.leave_family_for(auth.uid());
end $$;

revoke all on function public.create_family(text, text, text) from public, anon;
revoke all on function public.join_family(text, text, text) from public, anon;
revoke all on function public.leave_family() from public, anon;
grant execute on function public.create_family(text, text, text) to authenticated;
grant execute on function public.join_family(text, text, text) to authenticated;
grant execute on function public.leave_family() to authenticated;
grant execute on function public.is_family_member(uuid) to authenticated;

-- ═══════════════════════════ ROW LEVEL SECURITY ═══════════════════════════

alter table public.families              enable row level security;
alter table public.family_members        enable row level security;
alter table public.profiles              enable row level security;
alter table public.user_preferences      enable row level security;
alter table public.ingredient_categories enable row level security;
alter table public.ingredients           enable row level security;
alter table public.recipes               enable row level security;
alter table public.saved_recipes         enable row level security;
alter table public.meal_plans            enable row level security;
alter table public.meal_plan_items       enable row level security;
alter table public.shopping_lists        enable row level security;
alter table public.shopping_list_items   enable row level security;
alter table public.ai_conversations      enable row level security;
alter table public.ai_messages           enable row level security;
alter table public.ai_usage              enable row level security;

-- Anonymous (logged-out) clients get nothing.
revoke all on all tables in schema public from anon;
grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
revoke insert, update, delete on public.ai_usage, public.families, public.family_members, public.ingredient_categories from authenticated;
revoke insert, delete on public.profiles from authenticated;

-- Families: members can see their family.
drop policy if exists families_select on public.families;
create policy families_select on public.families for select to authenticated
  using (public.is_family_member(id));

drop policy if exists family_members_select on public.family_members;
create policy family_members_select on public.family_members for select to authenticated
  using (public.is_family_member(family_id));

-- Profiles: private to the user (children's details are never shared).
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles for select to authenticated using (id = auth.uid());
drop policy if exists profiles_update on public.profiles;
create policy profiles_update on public.profiles for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid() and (family_id is null or public.is_family_member(family_id)));

drop policy if exists prefs_all on public.user_preferences;
create policy prefs_all on public.user_preferences for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists categories_read on public.ingredient_categories;
create policy categories_read on public.ingredient_categories for select to authenticated using (true);

drop policy if exists ai_usage_read on public.ai_usage;
create policy ai_usage_read on public.ai_usage for select to authenticated using (user_id = auth.uid());

-- Family-shared tables: owner OR a member of the row's family.
do $$
declare t text;
begin
  foreach t in array array['ingredients','recipes','saved_recipes','meal_plans','meal_plan_items',
                           'shopping_lists','shopping_list_items']
  loop
    execute format('drop policy if exists %1$s_select on public.%1$s', t);
    execute format('create policy %1$s_select on public.%1$s for select to authenticated
      using (user_id = auth.uid() or (family_id is not null and public.is_family_member(family_id)))', t);

    execute format('drop policy if exists %1$s_insert on public.%1$s', t);
    execute format('create policy %1$s_insert on public.%1$s for insert to authenticated
      with check (user_id = auth.uid() and (family_id is null or public.is_family_member(family_id)))', t);

    execute format('drop policy if exists %1$s_update on public.%1$s', t);
    execute format('create policy %1$s_update on public.%1$s for update to authenticated
      using (user_id = auth.uid() or (family_id is not null and public.is_family_member(family_id)))
      with check ((family_id is null and user_id = auth.uid()) or (family_id is not null and public.is_family_member(family_id)))', t);

    execute format('drop policy if exists %1$s_delete on public.%1$s', t);
    execute format('create policy %1$s_delete on public.%1$s for delete to authenticated
      using (user_id = auth.uid() or (family_id is not null and public.is_family_member(family_id)))', t);
  end loop;
end $$;

-- Chef AI history: strictly private.
drop policy if exists ai_conversations_all on public.ai_conversations;
create policy ai_conversations_all on public.ai_conversations for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists ai_messages_all on public.ai_messages;
create policy ai_messages_all on public.ai_messages for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid()
              and exists (select 1 from public.ai_conversations c where c.id = conversation_id and c.user_id = auth.uid()));

-- ═══════════════════════════ STORAGE (avatars) ═══════════════════════════
-- Public-read bucket; users may only write inside a folder named after their user id.

insert into storage.buckets (id, name, public) values ('avatars', 'avatars', true)
on conflict (id) do nothing;

drop policy if exists avatars_read on storage.objects;
create policy avatars_read on storage.objects for select using (bucket_id = 'avatars');

drop policy if exists avatars_insert on storage.objects;
create policy avatars_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists avatars_update on storage.objects;
create policy avatars_update on storage.objects for update to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists avatars_delete on storage.objects;
create policy avatars_delete on storage.objects for delete to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
