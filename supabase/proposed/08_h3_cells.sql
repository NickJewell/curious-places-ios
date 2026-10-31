-- =============================================================================
-- PROPOSED — NOT APPLIED.
--
-- H3 hex cells for places. box_id is a fixed grid over London only (83 x 68
-- cells of about 690 m between lat 51.28-51.70 and lon -0.53-0.33; anything
-- outside is null). Each place gets two Uber H3 cells instead:
--   - h3_hex_r9_id: resolution 9, about 0.1 km² (edge about 200 m).
--   - h3_hex_r7_id: resolution 7, about 5 km² (edge about 1.4 km). It is the
--     PARENT of the r9 cell (cellToParent), not the r7 cell the point falls in,
--     so every r9 rolls up into exactly one r7. Near r7 edges the two can differ.
-- Both are the 15-character hex strings h3-js uses. They're text, not bigint,
-- because PostgREST sends bigint as a JSON number and JS loses precision
-- above 2^53.
--
-- Supabase has no h3 extension (checked on supabase/postgres:17.6.1.054, the
-- live version), so the cells are computed by the h3-index Edge Function
-- (supabase/functions/h3-index). The functions here are plain SQL over
-- h3_cells, a table the Edge Function fills with every r9 and r7 cell within
-- 2 rings of a cell that holds a place: its neighbours, r7 parent and outline.
--   - h3_cell_at(lat, lon, res)       the cell a point is in
--   - h3_neighbours(cell)             the cells touching a cell
--   - h3_grid_disk(cell, k)           cells within k rings (k <= 2), with distance
--   - places_near(lat, lon, k, res)   visible places in those cells, nearest first
-- LIMITATION: they only know cells within 2 rings of a place, so they return
-- nothing for a point far from every place. That's exact for places_near (a
-- cell further out has no places within 2 rings), but it can't be used to
-- walk empty regions; a loader working in new territory should use an H3
-- library directly. The radius is COVER_K in the Edge Function.
--
-- Keeping cells current: inserting a place, or changing its lat/lon, clears
-- its cells and asks h3-index to fill them in (through pg_net, once per
-- statement and at most every 30 seconds). Cells written by anything else are
-- cleared too. A pg_cron sweep every 5 minutes catches whatever a skipped or
-- failed request missed. Indexing never makes a write to places fail.
-- h3_cells only grows: cells around places that later move or are deleted
-- stay, which is harmless.
--
-- box_id is kept for now: the external loader still uses it.
--
-- Checked against the pulled live schema (migrations/20261031112705_remote_schema.sql):
--   - places' primary key is curio_id (text). lat and lon are double
--     precision, nullable. PostGIS is in public, and places already has a
--     generated location geography(Point) column.
--   - pg_net and pg_cron aren't enabled yet; both ship with Supabase.
--   - set_updated_at (BEFORE UPDATE on places) would stamp every row during the
--     backfill. It's recreated below to skip writes from apply_h3_cells.
--     That's the only change to an existing object.
--
-- After applying:
--   1. In the SQL editor (keep the values out of the repo):
--        select vault.create_secret('https://<project-ref>.supabase.co', 'project_url');
--        select vault.create_secret('<random secret>', 'h3_index_secret');
--   2. supabase secrets set H3_INDEX_SECRET=<the same secret>
--      supabase functions deploy h3-index --no-verify-jwt
--   3. Backfill: call the function until it returns "remaining": 0
--        curl -X POST https://<project-ref>.supabase.co/functions/v1/h3-index \
--          -H "x-h3-index-secret: <the secret>"
--
-- Before applying, worth a look (none of these block the file):
--   select count(*) as places, count(lat) as with_coordinates from places;
--   select count(*) filter (where box_id is distinct from               -- rows whose box_id
--     case when lat >= 51.28 and lat < 51.70 and lon >= -0.53 and lon < 0.33 -- isn't the admin
--     then floor((lat - 51.28) / 0.00619)::int * 83                     -- tool's formula
--        + floor((lon + 0.53) / 0.01045)::int + 1 end)
--   from places;
--
-- EXPO IMPACT: none. Its select('*') gains two columns it doesn't read.
-- =============================================================================

begin;

create extension if not exists pg_net with schema extensions;
create extension if not exists pg_cron with schema pg_catalog;

create schema if not exists private;

-- -----------------------------------------------------------------------------
-- Columns
-- -----------------------------------------------------------------------------
alter table public.places add column if not exists h3_hex_r7_id text;
alter table public.places add column if not exists h3_hex_r9_id text;

comment on column public.places.h3_hex_r7_id is
  'H3 resolution 7 cell: the parent of h3_hex_r9_id. Set by the h3-index Edge Function.';
comment on column public.places.h3_hex_r9_id is
  'H3 resolution 9 cell of (lat, lon). Set by the h3-index Edge Function.';

create index if not exists places_h3_hex_r7_id_idx on public.places (h3_hex_r7_id);
create index if not exists places_h3_hex_r9_id_idx on public.places (h3_hex_r9_id);

-- -----------------------------------------------------------------------------
-- h3_cells — cells within 2 rings of a place, at resolutions 7 and 9.
-- Anyone can read it; only the Edge Function (through apply_h3_cells) writes.
-- -----------------------------------------------------------------------------
create table if not exists public.h3_cells (
  h3_index text primary key,
  resolution smallint not null check (resolution in (7, 9)),
  parent_r7 text,
  neighbours text[] not null,
  boundary geography(Polygon, 4326) not null
);

comment on table public.h3_cells is
  'H3 cells within 2 rings of a place, filled by the h3-index Edge Function. See supabase/proposed/08_h3_cells.sql.';
comment on column public.h3_cells.parent_r7 is 'The r7 parent of an r9 cell; null for r7 cells.';
comment on column public.h3_cells.neighbours is 'The cells touching this one (6, or 5 at a pentagon).';

create index if not exists h3_cells_boundary_idx on public.h3_cells using gist (boundary);
create index if not exists h3_cells_parent_r7_idx on public.h3_cells (parent_r7);

alter table public.h3_cells enable row level security;

drop policy if exists "Anyone can read H3 cells" on public.h3_cells;
create policy "Anyone can read H3 cells"
  on public.h3_cells for select
  using (true);

revoke insert, update, delete, truncate on public.h3_cells from anon, authenticated;

-- -----------------------------------------------------------------------------
-- Read functions
-- -----------------------------------------------------------------------------

-- The cell at resolution `res` (7 or 9) that contains the point, or null if
-- it's further than 2 rings from every place. A point exactly on an edge gets
-- the lower index.
create or replace function public.h3_cell_at(lat double precision, lon double precision, res integer default 9)
returns text
language sql
stable
set search_path = public
as $$
  select c.h3_index
  from public.h3_cells c
  where c.resolution = h3_cell_at.res
    and st_covers(c.boundary, st_point(h3_cell_at.lon, h3_cell_at.lat)::geography)
  order by c.h3_index
  limit 1;
$$;

-- The cells touching `cell`.
create or replace function public.h3_neighbours(cell text)
returns setof text
language sql
stable
set search_path = public
as $$
  select unnest(c.neighbours) from public.h3_cells c where c.h3_index = h3_neighbours.cell;
$$;

-- `cell` and every cell within k rings of it, with its distance in rings.
-- k is limited to 2, the radius h3_cells covers around each place: further
-- out the walk could reach cells it has no neighbours for.
create or replace function public.h3_grid_disk(cell text, k integer default 1)
returns table (h3_index text, distance integer)
language plpgsql
stable
set search_path = public
as $$
begin
  if k is null or k < 0 or k > 2 then
    raise exception 'k must be between 0 and 2' using errcode = '22023';
  end if;

  return query
  with recursive walk (h3_index, distance) as (
    select h3_grid_disk.cell, 0
    union all
    select n.h3_index, w.distance + 1
    from walk w
    join public.h3_cells c on c.h3_index = w.h3_index
    cross join lateral unnest(c.neighbours) as n (h3_index)
    where w.distance < h3_grid_disk.k
  )
  select w.h3_index, min(w.distance)::integer
  from walk w
  where w.h3_index is not null
  group by w.h3_index
  order by 2, 1;
end;
$$;

-- Visible places in the point's cell and the cells within k rings of it,
-- nearest first. res 9 (the default) reaches about 200 m per ring, res 7
-- about 2.5 km. Returns places rows, so callers can pick columns:
--   rpc('places_near', { lat, lon, k: 1 }).select('curio_id,name,lat,lon')
create or replace function public.places_near(
  lat double precision,
  lon double precision,
  k integer default 1,
  res integer default 9
)
returns setof public.places
language plpgsql
stable
set search_path = public
as $$
declare
  origin text;
  cells text[];
begin
  if res is null or res not in (7, 9) then
    raise exception 'res must be 7 or 9' using errcode = '22023';
  end if;

  origin := public.h3_cell_at(places_near.lat, places_near.lon, places_near.res);
  if origin is null then
    return;
  end if;
  select array_agg(d.h3_index) into cells from public.h3_grid_disk(origin, places_near.k) d;

  if res = 9 then
    return query
    select p.* from public.places p
    where p.visible_flag and p.h3_hex_r9_id = any (cells)
    order by st_distance(p.location, st_point(places_near.lon, places_near.lat)::geography);
  else
    return query
    select p.* from public.places p
    where p.visible_flag and p.h3_hex_r7_id = any (cells)
    order by st_distance(p.location, st_point(places_near.lon, places_near.lat)::geography);
  end if;
end;
$$;

revoke execute on function public.h3_cell_at(double precision, double precision, integer) from public;
revoke execute on function public.h3_neighbours(text) from public;
revoke execute on function public.h3_grid_disk(text, integer) from public;
revoke execute on function public.places_near(double precision, double precision, integer, integer) from public;
grant execute on function public.h3_cell_at(double precision, double precision, integer) to anon, authenticated, service_role;
grant execute on function public.h3_neighbours(text) to anon, authenticated, service_role;
grant execute on function public.h3_grid_disk(text, integer) to anon, authenticated, service_role;
grant execute on function public.places_near(double precision, double precision, integer, integer) to anon, authenticated, service_role;

-- -----------------------------------------------------------------------------
-- apply_h3_cells — the Edge Function's write, one call per batch. Service role
-- only.
--   place_cells: [{ curio_id, lat, lon, r7, r9 }]
--   cells:       [{ h3_index, resolution, parent_r7, neighbours, boundary (WKT) }]
-- A place is only updated if its lat/lon still match the ones its cells were
-- computed from, so a place moved mid-run doesn't get stale cells.
-- Returns the number of places updated.
-- -----------------------------------------------------------------------------
create or replace function public.apply_h3_cells(place_cells jsonb, cells jsonb)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  updated integer;
begin
  insert into public.h3_cells (h3_index, resolution, parent_r7, neighbours, boundary)
  select c.h3_index, c.resolution, c.parent_r7, c.neighbours, st_geogfromtext(c.boundary)
  from jsonb_to_recordset(coalesce(cells, '[]')) as c (
    h3_index text, resolution smallint, parent_r7 text, neighbours text[], boundary text
  )
  on conflict (h3_index) do nothing;

  -- Tells set_updated_at to leave updated_at alone.
  perform set_config('curious_places.h3_write', 'on', true);

  update public.places p
  set h3_hex_r7_id = x.r7, h3_hex_r9_id = x.r9
  from jsonb_to_recordset(coalesce(place_cells, '[]')) as x (
    curio_id text, lat double precision, lon double precision, r7 text, r9 text
  )
  where p.curio_id = x.curio_id
    -- Not =: doubles are read out to 15 significant digits, so the value
    -- that comes back can differ from the stored one in the last bits.
    and abs(p.lat - x.lat) < 1e-9
    and abs(p.lon - x.lon) < 1e-9;
  get diagnostics updated = row_count;

  perform set_config('curious_places.h3_write', '', true);
  return updated;
end;
$$;

revoke execute on function public.apply_h3_cells(jsonb, jsonb) from public, anon, authenticated;
grant execute on function public.apply_h3_cells(jsonb, jsonb) to service_role;

-- -----------------------------------------------------------------------------
-- set_updated_at — as before, but skips apply_h3_cells' writes, so the
-- backfill doesn't stamp every place.
-- -----------------------------------------------------------------------------
drop trigger if exists set_updated_at on public.places;
create trigger set_updated_at
  before update on public.places
  for each row
  when (coalesce(current_setting('curious_places.h3_write', true), '') <> 'on')
  execute function public.update_updated_at_column();

-- -----------------------------------------------------------------------------
-- Keeping cells current
-- -----------------------------------------------------------------------------

-- New coordinates clear the cells; h3-index fills them in again.
create or replace function private.clear_h3_cells()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'INSERT'
     or new.lat is distinct from old.lat
     or new.lon is distinct from old.lon
     or new.h3_hex_r7_id is distinct from old.h3_hex_r7_id
     or new.h3_hex_r9_id is distinct from old.h3_hex_r9_id then
    new.h3_hex_r7_id := null;
    new.h3_hex_r9_id := null;
  end if;
  return new;
end;
$$;

-- When request_h3_index last called h3-index. One run indexes everything
-- pending, so a loader inserting row by row needn't call it for every row.
create table if not exists private.h3_index_requests (
  id boolean primary key default true check (id),
  last_requested_at timestamptz not null
);
insert into private.h3_index_requests (id, last_requested_at)
values (true, '-infinity')
on conflict (id) do nothing;

-- Asks h3-index to fill in missing cells, if there are any and it hasn't
-- been asked in the last 30 seconds. Never raises: without the Vault secrets
-- it does nothing, and any other failure is a warning. The sweep every 5
-- minutes catches what this misses or skips.
create or replace function private.request_h3_index()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  base_url text;
  secret text;
begin
  if not exists (
    select 1 from public.places
    where h3_hex_r9_id is null
      and lat between -90 and 90
      and lon between -180 and 180
  ) then
    return;
  end if;

  select decrypted_secret into base_url from vault.decrypted_secrets where name = 'project_url';
  select decrypted_secret into secret from vault.decrypted_secrets where name = 'h3_index_secret';
  if base_url is null or secret is null then
    return;
  end if;

  update private.h3_index_requests
  set last_requested_at = now()
  where last_requested_at < now() - interval '30 seconds';
  if not found then
    return;
  end if;

  perform net.http_post(
    url := rtrim(base_url, '/') || '/functions/v1/h3-index',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-h3-index-secret', secret),
    body := '{}'::jsonb,
    timeout_milliseconds := 150000
  );
exception when others then
  raise warning 'request_h3_index: %', sqlerrm;
end;
$$;

create or replace function private.queue_h3_index()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform private.request_h3_index();
  return null;
end;
$$;

revoke execute on function private.request_h3_index() from public;

drop trigger if exists clear_h3_cells on public.places;
create trigger clear_h3_cells
  before insert or update of lat, lon, h3_hex_r7_id, h3_hex_r9_id on public.places
  for each row
  when (coalesce(current_setting('curious_places.h3_write', true), '') <> 'on')
  execute function private.clear_h3_cells();

-- Once per statement, so a bulk insert makes one request (and the debounce in
-- request_h3_index covers row-by-row loads).
drop trigger if exists queue_h3_index on public.places;
create trigger queue_h3_index
  after insert or update of lat, lon on public.places
  for each statement
  execute function private.queue_h3_index();

-- When nothing is pending this is one indexed exists check.
select cron.schedule('h3-index-sweep', '*/5 * * * *', 'select private.request_h3_index()');

commit;
