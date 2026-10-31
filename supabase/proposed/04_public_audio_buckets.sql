-- =============================================================================
-- PROPOSED — NOT APPLIED.
--
-- Makes the narration audio buckets public, so the iOS app can stream files
-- from their public URLs with the anon key:
--   https://<project>.supabase.co/storage/v1/object/public/<bucket>/<file>
--
-- Public means anyone with a file's URL can download it. Listing a bucket's
-- contents still needs a storage.objects policy, and none is added here.
-- The Replit server's signed URLs keep working on public buckets.
--
-- Same change in the dashboard: Storage → <bucket> → Edit bucket → Public bucket.
--
-- Note: the Replit server creates missing language buckets as PRIVATE
-- (routes.ts:81-97). If it creates a new one after this runs, make that public too.
-- =============================================================================

update storage.buckets
set public = true
where id in (
    'en_audio', 'fr_audio', 'de_audio', 'it_audio', 'pt_audio', 'es_audio',
    'ja_audio', 'ar_audio', 'zh_audio', 'ko_audio', 'hi_audio'
  )
  or id like 'audio\_overviews\_%';   -- legacy pre-generated audio

-- Check: every audio bucket should now show public = true.
select id, public from storage.buckets
where id like '%\_audio' or id like 'audio\_overviews\_%'
order by id;
