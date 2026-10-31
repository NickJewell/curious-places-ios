-- =============================================================================
-- PROPOSED — NOT APPLIED. UNTESTED (written without access to the database).
--
-- Fixes the most serious bug in the inventory (§10, broken #1): duplicate
-- place IDs. The database becomes the only thing that hands out CURIO-<n>.
--
--   * Refuses to run while duplicates exist, so it can't hide them.
--   * Adds UNIQUE(curio_id). A buggy insert now fails loudly instead of
--     silently creating a second CURIO-1000.
--   * Adds a sequence-backed default, so inserts that omit curio_id get the
--     next number.
--
-- Run the duplicate query from the inventory first and resolve any duplicates
-- by hand. Each copy may have its own facts, check-ins and list items.
--
-- After applying, change both create endpoints in the Replit server
-- (POST /api/admin/place and POST /api/admin/places) to OMIT curio_id and read
-- it back from the insert. An explicit max+1 from the app can drift from the
-- sequence and hit the unique constraint.
-- =============================================================================

begin;

do $$
declare
  duplicate_ids int;
begin
  select count(*) into duplicate_ids
  from (
    select curio_id from public.places group by curio_id having count(*) > 1
  ) d;

  if duplicate_ids > 0 then
    raise exception '% curio_id value(s) are duplicated. Resolve them before applying this file.', duplicate_ids;
  end if;
end;
$$;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'places_curio_id_key' and conrelid = 'public.places'::regclass
  ) then
    alter table public.places add constraint places_curio_id_key unique (curio_id);
  end if;
end;
$$;

create sequence if not exists public.places_curio_number_seq;

-- Start after the highest existing number. Text sorting isn't involved here.
select setval('public.places_curio_number_seq', greatest(m, 1), m >= 1)
from (
  select coalesce(max((regexp_match(curio_id, '^CURIO-(\d+)$'))[1]::bigint), 0) as m
  from public.places
) s;

alter table public.places
  alter column curio_id set default ('CURIO-' || nextval('public.places_curio_number_seq'));

commit;
