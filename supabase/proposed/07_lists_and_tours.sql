-- =============================================================================
-- PROPOSED — NOT APPLIED.
--
-- Milestone 5 (lists and tours). Supersedes sections 3 and 4 of
-- 01_rls_policies.sql, whose stop policy compares lists.id (uuid) with
-- list_items.list_id (text) and can't be created.
--
-- Checked against the pulled live schema (migrations/20261031112705_remote_schema.sql),
-- which differs a lot from the Expo migration (create_lists_tables.sql):
--   - list_items has RLS on and NO policies, so nobody can read or write a row
--     with the anon key. Tours only work through the Replit server (service
--     role), and the Expo app's "Save to list" has never worked.
--   - list_items has no place_name/description/latitude/longitude, no `id`
--     (the key is list_item_uuid), and list_id is TEXT. Rows point at their
--     list through list_uuid, which is what the server reads (routes.ts:952, 993).
--   - There is no foreign key from list_items to lists, so deleting a list (or
--     an account, despite the comment in the account_and_admin migration)
--     leaves its items behind. There is no UNIQUE (list, place).
--   - lists has no metadata column. "Anyone can view official tours" exists.
--   - A user could create a list with list_type = 'tour' and it would become a
--     public "official tour".
--
-- The iOS app writes items with list_uuid = the list's id and list_id = the
-- same id as text (as the server's admin tool does), and reads them by
-- list_uuid.
--
-- Tour completion: a tour is complete when the user has checked in at every
-- visible stop. A trigger on checkins records it in tour_completions and
-- awards 'tour_complete' badges (Tour Guide). Clients can't write either.
--
-- Before applying, worth a look (none of these block the file):
--   select count(*) from list_items where list_uuid is null;      -- rows no app can see
--   select list_uuid, place_id, count(*) from list_items
--     group by 1, 2 having count(*) > 1;                          -- blocks the unique index
--
-- EXPO IMPACT: none. The Expo app reads tours through the server and its list
-- item inserts use columns that don't exist.
-- =============================================================================

begin;

-- -----------------------------------------------------------------------------
-- 1. lists — users create and edit only their own plain lists. Tours stay with
--    the service role (admin tools). The public tours read is unchanged.
-- -----------------------------------------------------------------------------
drop policy if exists "Users can create own lists" on public.lists;
create policy "Users can create own lists" on public.lists
  for insert to authenticated
  with check (auth.uid() = user_id and coalesce(list_type, 'list') = 'list');

drop policy if exists "Users can update own lists" on public.lists;
create policy "Users can update own lists" on public.lists
  for update to authenticated
  using (auth.uid() = user_id and coalesce(list_type, 'list') = 'list')
  with check (auth.uid() = user_id and coalesce(list_type, 'list') = 'list');

drop policy if exists "Users can delete own lists" on public.lists;
create policy "Users can delete own lists" on public.lists
  for delete to authenticated
  using (auth.uid() = user_id and coalesce(list_type, 'list') = 'list');

-- -----------------------------------------------------------------------------
-- 2. list_items — anyone may read tour stops; owners manage their own lists'
--    items. All matched on list_uuid.
-- -----------------------------------------------------------------------------
drop policy if exists "Anyone can view official tour stops" on public.list_items;
create policy "Anyone can view official tour stops" on public.list_items
  for select to anon, authenticated
  using (exists (
    select 1 from public.lists l
    where l.id = list_items.list_uuid and l.list_type = 'tour'
  ));

drop policy if exists "Users can view items in own lists" on public.list_items;
create policy "Users can view items in own lists" on public.list_items
  for select to authenticated
  using (exists (
    select 1 from public.lists l
    where l.id = list_items.list_uuid and l.user_id = auth.uid()
  ));

drop policy if exists "Users can add items to own lists" on public.list_items;
create policy "Users can add items to own lists" on public.list_items
  for insert to authenticated
  with check (
    list_id = list_uuid::text
    and exists (
      select 1 from public.lists l
      where l.id = list_items.list_uuid and l.user_id = auth.uid()
        and coalesce(l.list_type, 'list') = 'list'
    )
  );

drop policy if exists "Users can update items in own lists" on public.list_items;
create policy "Users can update items in own lists" on public.list_items
  for update to authenticated
  using (exists (
    select 1 from public.lists l
    where l.id = list_items.list_uuid and l.user_id = auth.uid()
      and coalesce(l.list_type, 'list') = 'list'
  ))
  with check (
    list_id = list_uuid::text
    and exists (
      select 1 from public.lists l
      where l.id = list_items.list_uuid and l.user_id = auth.uid()
        and coalesce(l.list_type, 'list') = 'list'
    )
  );

drop policy if exists "Users can delete items from own lists" on public.list_items;
create policy "Users can delete items from own lists" on public.list_items
  for delete to authenticated
  using (exists (
    select 1 from public.lists l
    where l.id = list_items.list_uuid and l.user_id = auth.uid()
      and coalesce(l.list_type, 'list') = 'list'
  ));

-- -----------------------------------------------------------------------------
-- 3. Deleting a list deletes its items. NOT VALID skips checking existing rows
--    (orphans from earlier deletes stay put) but cascades from now on.
-- -----------------------------------------------------------------------------
alter table public.list_items drop constraint if exists list_items_list_uuid_fkey;
alter table public.list_items
  add constraint list_items_list_uuid_fkey
  foreign key (list_uuid) references public.lists (id) on delete cascade not valid;

create index if not exists idx_list_items_list_uuid_order
  on public.list_items (list_uuid, order_index);

-- -----------------------------------------------------------------------------
-- 4. A place appears once per list. Skipped, with a notice, if duplicates
--    already exist; the app checks before inserting either way.
-- -----------------------------------------------------------------------------
do $$
begin
  if exists (
    select 1 from public.list_items
    group by list_uuid, place_id having count(*) > 1
  ) then
    raise notice 'list_items has duplicate (list_uuid, place_id) rows; unique index not created';
  else
    create unique index if not exists list_items_list_uuid_place_id_key
      on public.list_items (list_uuid, place_id);
  end if;
end;
$$;

-- -----------------------------------------------------------------------------
-- 5. Tour completions, recorded by the database.
-- -----------------------------------------------------------------------------
create table if not exists public.tour_completions (
  user_id uuid not null references auth.users (id) on delete cascade,
  tour_id uuid not null references public.lists (id) on delete cascade,
  completed_at timestamptz not null default now(),
  primary key (user_id, tour_id)
);

alter table public.tour_completions enable row level security;

drop policy if exists "Users can view their own tour completions" on public.tour_completions;
create policy "Users can view their own tour completions" on public.tour_completions
  for select to authenticated
  using (auth.uid() = user_id);

-- The tours `user_id` has checked in at every visible stop of. A tour with no
-- visible stops is never complete.
create or replace function public.completed_tours(uid uuid)
returns table (tour_id uuid)
language sql
stable
security definer
set search_path = public
as $$
  select l.id
  from lists l
  where l.list_type = 'tour'
    and exists (
      select 1 from list_items li
      join places p on p.curio_id = li.place_id and p.visible_flag
      where li.list_uuid = l.id
    )
    and not exists (
      select 1 from list_items li
      join places p on p.curio_id = li.place_id and p.visible_flag
      where li.list_uuid = l.id
        and not exists (
          select 1 from checkins c where c.user_id = uid and c.place_id = li.place_id
        )
    );
$$;

-- Only the trigger and the backfill below need it.
revoke execute on function public.completed_tours(uuid) from public, anon, authenticated;

create or replace function public.record_tour_completions()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.tour_completions (user_id, tour_id)
  select new.user_id, t.tour_id
  from public.completed_tours(new.user_id) t
  on conflict (user_id, tour_id) do nothing;

  insert into public.user_badges (user_id, badge_id)
  select new.user_id, b.id
  from public.badges b
  where b.requirement_type = 'tour_complete'
    and b.requirement_value <= (
      select count(*) from public.tour_completions tc where tc.user_id = new.user_id
    )
  on conflict (user_id, badge_id) do nothing;

  return new;
end;
$$;

drop trigger if exists record_tour_completions on public.checkins;
create trigger record_tour_completions
  after insert on public.checkins
  for each row execute function public.record_tour_completions();

-- One-off: tours already completed by earlier check-ins, and their badges.
insert into public.tour_completions (user_id, tour_id)
select u.user_id, t.tour_id
from (select distinct user_id from public.checkins) u
cross join lateral public.completed_tours(u.user_id) t
on conflict (user_id, tour_id) do nothing;

insert into public.user_badges (user_id, badge_id)
select totals.user_id, b.id
from (select user_id, count(*) as n from public.tour_completions group by user_id) totals
join public.badges b
  on b.requirement_type = 'tour_complete' and b.requirement_value <= totals.n
on conflict (user_id, badge_id) do nothing;

commit;
