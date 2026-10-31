-- =============================================================================
-- PROPOSED — NOT APPLIED.
--
-- Milestone 4 (compass hunt, check-ins and badges) on its own. Sections 5, 9
-- and 10 of 01_rls_policies.sql, pulled out so they can be applied without the
-- rest of that file, plus a one-off badge backfill. Every statement is
-- re-runnable, so applying both files is harmless.
--
-- Checked against the pulled live schema (migrations/20261031112705_remote_schema.sql):
--   - checkins has SELECT and INSERT policies but NO DELETE policy, so
--     "Remove check-in" deletes nothing. The iOS app reports that as an error.
--   - user_badges has "Users can insert their own badges", so any signed-in
--     user can award themselves any badge.
--   - get_user_progress is SECURITY DEFINER with no caller check, so anyone
--     can read anyone's progress.
--   - There is no trigger on checkins.
--
-- The iOS app never inserts into user_badges. Until this is applied, check-ins
-- from iOS earn no badges (the trigger below catches up on the next check-in,
-- and the backfill catches up everyone straight away).
--
-- EXPO IMPACT: removing a check-in starts working. The Expo app's own award
-- step finds the badges already earned and skips its insert. The Expo profile
-- keeps working because it only reads its own progress.
-- =============================================================================

begin;

-- -----------------------------------------------------------------------------
-- checkins — users can remove their own check-ins.
-- -----------------------------------------------------------------------------
drop policy if exists "Users can delete their own checkins" on public.checkins;
create policy "Users can delete their own checkins" on public.checkins
  for delete to authenticated
  using (auth.uid() = user_id);

-- -----------------------------------------------------------------------------
-- user_badges — awarded by the database after each check-in, not by clients.
-- Removing a check-in doesn't take a badge away (the Expo app didn't either).
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

-- One-off: award anything already earned but missing, e.g. check-ins made
-- from iOS before this file was applied.
insert into public.user_badges (user_id, badge_id)
select totals.user_id, b.id
from (select user_id, count(*) as n from public.checkins group by user_id) totals
join public.badges b
  on b.requirement_type = 'checkin_count' and b.requirement_value <= totals.n
on conflict (user_id, badge_id) do nothing;

-- -----------------------------------------------------------------------------
-- get_user_progress — callers can read only their own progress. Same body as
-- create_checkins_badges_tables.sql:75-108, plus the check and a fixed
-- search_path. The iOS app doesn't call it; this is for the Expo app.
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
