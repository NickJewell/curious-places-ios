-- =============================================================================
-- PROPOSED — NOT APPLIED. UNTESTED (written without access to the database).
--
-- 1. delete_own_account(): lets a signed-in user delete their own account from
--    the app, as App Store guideline 5.1.1(v) requires.
-- 2. is_admin(): the server-side admin rule, for the admin write policies in a
--    later milestone. It matches AdminAccess in the iOS app.
--
-- RELEASE BLOCKER, not covered here: for users who signed in with Apple, Apple
-- also requires their Sign in with Apple tokens to be revoked when the account
-- is deleted. That needs a server call with Apple's client secret (an Edge
-- Function), so it can't be done in SQL.
-- =============================================================================

begin;

-- -----------------------------------------------------------------------------
-- 1. delete_own_account()
--    lists, list_items, checkins and user_badges go automatically
--    (ON DELETE CASCADE from auth.users). content_votes and issues have no
--    migration (their columns are INFERRED), so each cleanup step tolerates the
--    table being missing. The auth.users delete still happens either way.
-- -----------------------------------------------------------------------------
create or replace function public.delete_own_account()
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'Not signed in' using errcode = '42501';
  end if;

  begin
    delete from public.content_votes where user_id = uid;
  exception when undefined_table or undefined_column then null;
  end;

  begin
    -- Keep the reports; drop who sent them.
    update public.issues set user_id = null where user_id = uid;
  exception when undefined_table or undefined_column then null;
  end;

  delete from public.profiles where id = uid;
  delete from auth.users where id = uid;
end;
$$;

revoke execute on function public.delete_own_account() from public, anon;
grant execute on function public.delete_own_account() to authenticated;

-- -----------------------------------------------------------------------------
-- 2. is_admin()
--    True for profiles.admin_flag, or for Nick's address with a verified email,
--    however he signed in (Apple, Google and email can be separate accounts).
--    A Sign in with Apple account using "Hide My Email" has a relay address and
--    won't match; set admin_flag on that profile instead.
-- -----------------------------------------------------------------------------
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid() and p.admin_flag = true
    )
    or exists (
      select 1 from auth.users u
      where u.id = auth.uid()
        and lower(u.email) in ('nick.jewell@gmail.com')
        and u.email_confirmed_at is not null
    );
$$;

revoke execute on function public.is_admin() from public;
grant execute on function public.is_admin() to anon, authenticated;

commit;
