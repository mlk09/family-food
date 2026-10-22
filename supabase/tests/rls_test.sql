-- RLS isolation tests. Run after supabase_stubs.sql + schema.sql:
--   psql -v ON_ERROR_STOP=1 -f supabase/tests/rls_test.sql
-- Raises an exception (non-zero exit) on any failed expectation.
\set QUIET on
\pset tuples_only on
\pset format unaligned
begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('11111111-1111-4111-8111-111111111111', 'dad@sharma.test',  '{"name":"Raj"}'),
  ('22222222-2222-4222-8222-222222222222', 'mom@sharma.test',  '{"name":"Priya"}'),
  ('33333333-3333-4333-8333-333333333333', 'other@verma.test', '{"name":"Stranger"}');

create or replace function pg_temp.act_as(u uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', u::text, true);
  execute 'set local role authenticated';
end $$;

create or replace function pg_temp.expect(cond boolean, msg text) returns void language plpgsql as $$
begin
  if not cond then raise exception 'FAILED: %', msg; end if;
  raise notice 'ok - %', msg;
end $$;

-- Trigger created profiles + preferences.
select pg_temp.expect((select count(*) from public.profiles where name in ('Raj','Priya','Stranger')) = 3, 'profiles auto-created on signup');

-- Dad adds a private ingredient and a shopping item.
select pg_temp.act_as('11111111-1111-4111-8111-111111111111');
insert into public.ingredients (name, quantity, unit, category) values ('Potato', 5, 'pieces', 'vegetables');
insert into public.shopping_list_items (name) values ('Paneer');
select pg_temp.expect((select list_id from public.shopping_list_items where name = 'Paneer') is not null, 'shopping item auto-assigned to a list');

-- Stranger cannot see or touch Dad's data.
reset role;
select pg_temp.act_as('33333333-3333-4333-8333-333333333333');
select pg_temp.expect((select count(*) from public.ingredients) = 0, 'stranger sees no private ingredients');
select pg_temp.expect((select count(*) from public.profiles) = 1, 'stranger sees only own profile');
update public.ingredients set quantity = 99;
delete from public.ingredients;
reset role;
select pg_temp.expect((select quantity from public.ingredients where name = 'Potato') = 5, 'stranger cannot update/delete others rows');

-- Stranger cannot insert a row claiming to be Dad.
select pg_temp.act_as('33333333-3333-4333-8333-333333333333');
do $$ begin
  insert into public.ingredients (user_id, name) values ('11111111-1111-4111-8111-111111111111', 'Fake');
  raise exception 'FAILED: spoofed insert allowed';
exception when insufficient_privilege then raise notice 'ok - spoofed user_id insert blocked';
end $$;
reset role;

-- Dad creates a family; his rows become shared.
select pg_temp.act_as('11111111-1111-4111-8111-111111111111');
create temp table fam on commit drop as select * from public.create_family('Sharma Family', 'Raj', 'dad');
grant select on fam to authenticated;
reset role;
select pg_temp.expect((select family_id from public.ingredients where name = 'Potato') = (select id from fam), 'dad rows moved into family');

-- Mom joins with the invite code and sees the shared kitchen + list.
select pg_temp.act_as('22222222-2222-4222-8222-222222222222');
select public.join_family((select invite_code from fam), 'Priya', 'mom');
select pg_temp.expect((select count(*) from public.ingredients where name = 'Potato') = 1, 'family member sees shared ingredient');
select pg_temp.expect((select count(*) from public.shopping_list_items where name = 'Paneer') = 1, 'family member sees shared shopping list');
select pg_temp.expect((select count(*) from public.family_members) = 2, 'family member sees both members');
-- Mom edits Dad's ingredient: allowed, owner preserved.
update public.ingredients set quantity = 3 where name = 'Potato';
reset role;
select pg_temp.expect((select quantity from public.ingredients where name = 'Potato') = 3, 'family member can update shared row');
select pg_temp.expect((select user_id from public.ingredients where name = 'Potato') = '11111111-1111-4111-8111-111111111111', 'owner preserved on edit');

-- Mom cannot read Dad's profile or AI chats.
select pg_temp.act_as('11111111-1111-4111-8111-111111111111');
insert into public.ai_conversations (id, title) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Dinner ideas');
insert into public.ai_messages (conversation_id, role, content) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'user', 'hi');
reset role;
select pg_temp.act_as('22222222-2222-4222-8222-222222222222');
select pg_temp.expect((select count(*) from public.ai_messages) = 0, 'AI chats are private even within a family');
select pg_temp.expect((select count(*) from public.profiles) = 1, 'profiles are private even within a family');

-- Stranger still sees nothing, and cannot join without the code.
reset role;
select pg_temp.act_as('33333333-3333-4333-8333-333333333333');
select pg_temp.expect((select count(*) from public.ingredients) = 0, 'stranger still isolated from family');
select pg_temp.expect((select count(*) from public.families) = 0, 'stranger cannot list families');
do $$ begin
  perform public.join_family('ZZZZZZ', 'x', 'member');
  raise exception 'FAILED: bad invite code accepted';
exception when raise_exception then
  if sqlerrm not like '%invalid_code%' then raise; end if;
  raise notice 'ok - invalid invite code rejected';
end $$;

-- Stranger cannot move a row into the Sharma family.
insert into public.ingredients (name) values ('Rice');
do $$ begin
  update public.ingredients set family_id = (select id from pg_temp.fam) where name = 'Rice';
  raise exception 'FAILED: moved row into foreign family';
exception when insufficient_privilege then raise notice 'ok - cannot move rows into a foreign family';
end $$;
reset role;

-- Anonymous role has no table access.
set local role anon;
do $$ begin
  perform 1 from public.ingredients;
  raise exception 'FAILED: anon can read ingredients';
exception when insufficient_privilege then raise notice 'ok - anon has no access';
end $$;
reset role;

-- Mom leaves: loses access to Dad's items.
select pg_temp.act_as('22222222-2222-4222-8222-222222222222');
select public.leave_family();
select pg_temp.expect((select count(*) from public.ingredients where name = 'Potato') = 0, 'leaving family removes access');
reset role;

rollback;
\echo 'ALL RLS TESTS PASSED'
