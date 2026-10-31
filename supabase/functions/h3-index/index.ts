// h3-index: fills in places.h3_hex_r9_id and h3_hex_r7_id, and the h3_cells
// table the SQL neighbour functions read (supabase/proposed/08_h3_cells.sql).
// Supabase has no h3 extension, so the H3 maths happens here, with h3-js.
//
// POST (no body) → { indexed, cells, remaining }
//   Indexes places whose h3_hex_r9_id is null, in batches, for up to about
//   100 s. "remaining" > 0 means call again. It takes no input and only
//   touches unindexed places, so repeated or concurrent calls are harmless.
//
// Called by the database (a trigger on places, and an hourly pg_cron sweep,
// through pg_net) and by hand for the backfill. Callers send the
// x-h3-index-secret header, which must match H3_INDEX_SECRET.
//
// Secrets: H3_INDEX_SECRET (`supabase secrets set H3_INDEX_SECRET=...`, and
// the same value in Vault as h3_index_secret).
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are provided by the platform.
// Deploy: `supabase functions deploy h3-index --no-verify-jwt`. The secret
// header replaces JWT verification: the database has no user session to send,
// and the project's publishable key isn't a JWT.

import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { cellToBoundary, cellToParent, getResolution, gridDisk, latLngToCell } from "npm:h3-js@4";

/** The resolutions stored on places. r7 is the parent of r9, not the point's own r7 cell. */
const FINE_RES = 9;
const COARSE_RES = 7;
/**
 * h3_cells covers every cell within this many rings of a place. The SQL
 * h3_grid_disk refuses k above it, so raise both together.
 */
const COVER_K = 2;
/**
 * Places per apply_h3_cells call. Each updated place also updates every index
 * on places, including the HNSW index on detail_overview_vector, which is
 * slow; 500 at a time can run into the statement timeout.
 */
const BATCH_SIZE = 100;
const TIME_BUDGET_MS = 100_000;

type PlaceRow = { curio_id: string; lat: number; lon: number };
type PlaceCells = PlaceRow & { r7: string; r9: string };
type CellRow = {
  h3_index: string;
  resolution: number;
  parent_r7: string | null;
  neighbours: string[];
  boundary: string;
};

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const secret = Deno.env.get("H3_INDEX_SECRET");
  if (!secret) return json({ error: "H3 indexing isn't configured" }, 503);
  if (!sameString(req.headers.get("x-h3-index-secret") ?? "", secret)) {
    return json({ error: "Unauthorized" }, 401);
  }

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  try {
    return json(await indexPlaces(admin));
  } catch (error) {
    console.error("[h3-index]", error);
    // Callers already hold the secret, so the detail isn't sensitive.
    return json({ error: "Internal error", detail: describe(error) }, 500);
  }
});

/** Errors from supabase-js are plain objects, not Errors. */
function describe(error: unknown): string {
  if (error instanceof Error) return error.message;
  if (error && typeof error === "object" && "message" in error) {
    const { code, message } = error as { code?: string; message: string };
    return code ? `${code}: ${message}` : message;
  }
  return String(error);
}

async function indexPlaces(admin: SupabaseClient) {
  const started = Date.now();
  let indexed = 0;
  let cells = 0;

  while (Date.now() - started < TIME_BUDGET_MS) {
    const rows = await unindexed(admin, BATCH_SIZE);
    if (rows.length === 0) break;

    const placeCells = rows.map(cellsFor);
    const cellRows = coverage(placeCells);
    const { data: updated, error } = await admin.rpc("apply_h3_cells", {
      place_cells: placeCells,
      cells: cellRows,
    });
    if (error) throw error;

    indexed += updated as number;
    cells += cellRows.length;
    // Nothing updated means every row moved mid-run or can't be matched;
    // fetching again would return the same rows forever.
    if (updated === 0) break;
  }

  const { count, error } = await pending(admin, "curio_id", { count: "exact", head: true });
  if (error) throw error;
  return { indexed, cells, remaining: count ?? 0 };
}

/** Places without cells and with coordinates H3 can index (as in private.request_h3_index). */
function pending(admin: SupabaseClient, columns: string, options?: { count: "exact"; head: boolean }) {
  return admin
    .from("places")
    .select(columns, options)
    .is("h3_hex_r9_id", null)
    .gte("lat", -90).lte("lat", 90)
    .gte("lon", -180).lte("lon", 180);
}

async function unindexed(admin: SupabaseClient, limit: number): Promise<PlaceRow[]> {
  const { data, error } = await pending(admin, "curio_id, lat, lon")
    .order("curio_id")
    .limit(limit);
  if (error) throw error;
  return data as unknown as PlaceRow[];
}

function cellsFor(place: PlaceRow): PlaceCells {
  const r9 = latLngToCell(place.lat, place.lon, FINE_RES);
  return { ...place, r9, r7: cellToParent(r9, COARSE_RES) };
}

/** Every r9 and r7 cell within COVER_K rings of the batch's places. */
function coverage(places: PlaceCells[]): CellRow[] {
  const occupied = new Set(places.flatMap((p) => [p.r9, p.r7]));
  const covered = new Set<string>();
  for (const cell of occupied) {
    for (const c of gridDisk(cell, COVER_K)) covered.add(c);
  }
  return [...covered].map(cellRow);
}

function cellRow(cell: string): CellRow {
  const resolution = getResolution(cell);
  return {
    h3_index: cell,
    resolution,
    parent_r7: resolution === FINE_RES ? cellToParent(cell, COARSE_RES) : null,
    neighbours: gridDisk(cell, 1).filter((c) => c !== cell),
    boundary: polygonWKT(cell),
  };
}

/** The cell's outline as WKT, in lon/lat order and closed. */
function polygonWKT(cell: string): string {
  const ring = cellToBoundary(cell, true);
  ring.push(ring[0]);
  return `SRID=4326;POLYGON((${ring.map(([lon, lat]) => `${lon} ${lat}`).join(",")}))`;
}

function sameString(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
