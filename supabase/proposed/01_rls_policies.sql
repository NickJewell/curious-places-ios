-- =============================================================================
-- PROPOSED — NOT APPLIED. UNTESTED (written without access to the database).
--
-- RLS policies so the iOS app can work with the anon key only (decision D2 in
-- docs/migration/01-inventory.md), plus fixes for the RLS gaps listed in §10.
--
-- Before applying:
--   1. Run `supabase db pull` so the live schema is baselined. Several tables
--      here (places, facts, content_votes, issues, profiles) have no migration
--      in the Expo repo; their columns are INFERRED from code.
--   2. Read each section. Sections marked EXPO IMPACT change how the existing
--      Expo app behaves.
--   3. Apply in the SQL editor, or move this file into supabase/migrations/
--      with a timestamp later than the pulled baseline.
--
-- Every statement is re-runnable (DROP POLICY IF EXISTS + CREATE POLICY).
-- The Replit server uses the service-role key, which bypasses RLS, so none of
-- this affects the server.
-- =============================================================================

begin;

-- -----------------------------------------------------------------------------
-- 1. places — anyone may read visible places. No write policies: writes stay
--    with the service role (admin tools).
-- -----------------------------------------------------------------------------
alter table public.places enable row level security;

drop policy if exists "Public can read visible places" on public.places;
create policy "Public can read visible places" on public.places
  for select to anon, authenticated
  using (visible_flag = true);

-- -----------------------------------------------------------------------------
-- 2. facts — readable when their place is visible.
-- -----------------------------------------------------------------------------
alter table public.facts enable row level security;

drop policy if exists "Public can read facts of visible places" on public.facts;
create policy "Public can read facts of visible places" on public.facts
  for select to anon, authenticated
  using (exists (
    select 1 from public.places p
    where p.curio_id = facts.curio_id and p.visible_flag = true
  ));

-- -----------------------------------------------------------------------------
-- 3. Official tours — public read of tour lists and their stops.
--    Replaces add_tours_columns.sql:32, which used CREATE POLICY IF NOT EXISTS
--    (invalid in Postgres) and so probably never applied.
--    Stops are matched on list_id, which the migration makes NOT NULL and the
--    admin tool sets alongside list_uuid (routes.ts:1232-1235). If `db pull`
--    shows tour items with a NULL list_id, extend this to list_uuid.
-- -----------------------------------------------------------------------------
drop policy if exists "Anyone can view official tours" on public.lists;
create policy "Anyone can view official tours" on public.lists
  for select to anon, authenticated
  using (list_type = 'tour');

drop policy if exists "Anyone can view official tour stops" on public.list_items;
create policy "Anyone can view official tour stops" on public.list_items
  for select to anon, authenticated
  using (exists (
    select 1 from public.lists l
    where l.id = list_items.list_id and l.list_type = 'tour'
  ));

-- -----------------------------------------------------------------------------
-- 4. lists — UPDATE had no WITH CHECK, so an owner could reassign user_id.
-- -----------------------------------------------------------------------------
drop policy if exists "Users can update own lists" on public.lists;
create policy "Users can update own lists" on public.lists
  for update to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- -----------------------------------------------------------------------------
-- 5. checkins — there was no DELETE policy, so "remove check-in" silently did
--    nothing (inventory §10, broken #2).
--    EXPO IMPACT: removing a check-in in the Expo app starts working.
-- -----------------------------------------------------------------------------
drop policy if exists "Users can delete their own checkins" on public.checkins;
create policy "Users can delete their own checkins" on public.checkins
  for delete to authenticated
  using (auth.uid() = user_id);

-- -----------------------------------------------------------------------------
-- 6. content_votes — signed-in users manage their own votes.
--    Guests can no longer vote from the iOS app (the server accepted votes
--    with no user). EXPO IMPACT: none; the Expo app votes through the server.
-- -----------------------------------------------------------------------------
alter table public.content_votes enable row level security;

drop policy if exists "Users can read their own votes" on public.content_votes;
create policy "Users can read their own votes" on public.content_votes
  for select to authenticated
  using (auth.uid() = user_id);

drop policy if exists "Users can add their own votes" on public.content_votes;
create policy "Users can add their own votes" on public.content_votes
  for insert to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "Users can remove their own votes" on public.content_votes;
create policy "Users can remove their own votes" on public.content_votes
  for delete to authenticated
  using (auth.uid() = user_id);

-- -----------------------------------------------------------------------------
-- 7. issues — anyone may report; a report can't claim to be from another user.
--    No read policy: reports are only read by admins via the service role.
-- -----------------------------------------------------------------------------
alter table public.issues enable row level security;

drop policy if exists "Anyone can report issues" on public.issues;
create policy "Anyone can report issues" on public.issues
  for insert to anon, authenticated
  with check (user_id is null or user_id = auth.uid());

-- -----------------------------------------------------------------------------
-- 8. profiles — users read and edit only their own row, and can never set
--    admin_flag themselves. Column grants matter here: with a plain
--    "update own row" policy, anyone could promote themselves to admin.
--    `id` is in the grants because supabase-js/swift upserts send it.
--    If `db pull` shows other client-editable columns, add them to the grants.
-- -----------------------------------------------------------------------------
alter table public.profiles enable row level security;

drop policy if exists "Users can read own profile" on public.profiles;
create policy "Users can read own profile" on public.profiles
  for select to authenticated
  using (auth.uid() = id);

drop policy if exists "Users can create own profile" on public.profiles;
create policy "Users can create own profile" on public.profiles
  for insert to authenticated
  with check (auth.uid() = id);

drop policy if exists "Users can update own profile" on public.profiles;
create policy "Users can update own profile" on public.profiles
  for update to authenticated
  using (auth.uid() = id)
  with check (auth.uid() = id);

revoke insert, update on public.profiles from anon, authenticated;
grant insert (id, email, full_name, avatar_url, preferred_language) on public.profiles to authenticated;
grant update (id, email, full_name, avatar_url, preferred_language) on public.profiles to authenticated;

-- -----------------------------------------------------------------------------
-- 9. Badges are awarded by the database, not the client.
--    The old policy let any signed-in user insert any badge for themselves.
--    A trigger now awards check-in-count badges after each check-in.
--    EXPO IMPACT: the Expo app's own award step finds the badges already
--    earned and skips its insert, so it keeps working.
-- -----------------------------------------------------------------------------
drop policy if exists "Users can insert their own badges" on public.user_badges;

create or replace function public.award_checkin_badges()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.user_badges (user_id, badge_id)
  select new.user_id, b.id
  from public.badges b
  where b.requirement_type = 'checkin_count'
    and b.requirement_value <= (
      select count(*) from public.checkins c where c.user_id = new.user_id
    )
  on conflict (user_id, badge_id) do nothing;
  return new;
end;
$$;

drop trigger if exists award_checkin_badges on public.checkins;
create trigger award_checkin_badges
  after insert on public.checkins
  for each row execute function public.award_checkin_badges();

-- -----------------------------------------------------------------------------
-- 10. get_user_progress — was SECURITY DEFINER with no caller check, so anyone
--     could read anyone's progress. Same body as
--     create_checkins_badges_tables.sql:75-108, plus the check and a fixed
--     search_path.
-- -----------------------------------------------------------------------------
create or replace function public.get_user_progress(uid uuid)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  result json;
begin
  if uid is distinct from auth.uid() then
    raise exception 'You can only read your own progress' using errcode = '42501';
  end if;

  select json_build_object(
    'total_checkins', (select count(*) from checkins where user_id = uid),
    'total_badges', (select count(*) from user_badges where user_id = uid),
    'badges', (
      select coalesce(json_agg(json_build_object(
        'id', b.id,
        'name', b.name,
        'description', b.description,
        'icon_name', b.icon_name,
        'earned_at', ub.earned_at
      )), '[]'::json)
      from user_badges ub
      join badges b on b.id = ub.badge_id
      where ub.user_id = uid
    ),
    'recent_checkins', (
      select coalesce(json_agg(json_build_object(
        'id', c.id,
        'place_id', c.place_id,
        'place_name', c.place_name,
        'checked_in_at', c.checked_in_at
      ) order by c.checked_in_at desc), '[]'::json)
      from (select * from checkins where user_id = uid order by checked_in_at desc limit 20) c
    )
  ) into result;

  return result;
end;
$$;

commit;

-- Not covered here (later milestones): Storage read access for the audio
-- buckets, admin write policies gated on profiles.admin_flag, and an Edge
-- Function for text-to-speech.
