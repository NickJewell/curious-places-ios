-- =============================================================================
-- PROPOSED — NOT APPLIED.
--
-- Milestone 3 (place detail) on its own: the vote and issue-report policies.
-- Identical to sections 6 and 7 of 01_rls_policies.sql, pulled out so they can
-- be applied without the rest of that file. Applying both files is harmless:
-- every statement is re-runnable.
--
-- Checked against the pulled live schema (migrations/20261031112705_remote_schema.sql):
--   - issues has RLS enabled and NO policies, so every insert from the app is
--     refused until this runs.
--   - content_votes has "Anyone can read / insert / delete votes" USING (true),
--     so anyone can read or delete anyone's votes. Those are replaced below.
--
-- EXPO IMPACT: none. The Expo app votes and reports through the Replit server,
-- which uses the service-role key and bypasses RLS.
-- =============================================================================

begin;

-- -----------------------------------------------------------------------------
-- content_votes — signed-in users manage only their own votes.
-- -----------------------------------------------------------------------------
alter table public.content_votes enable row level security;

drop policy if exists "Anyone can read votes" on public.content_votes;
drop policy if exists "Anyone can insert votes" on public.content_votes;
drop policy if exists "Anyone can delete votes" on public.content_votes;

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
-- issues — anyone may report; a report can't claim to be from another user.
-- No read policy: reports are read by admins via the service role.
-- -----------------------------------------------------------------------------
alter table public.issues enable row level security;

drop policy if exists "Anyone can report issues" on public.issues;
create policy "Anyone can report issues" on public.issues
  for insert to anon, authenticated
  with check (user_id is null or user_id = auth.uid());

commit;
