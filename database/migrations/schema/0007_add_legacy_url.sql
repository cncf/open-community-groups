-- Add legacy_url column to group (optional).
alter table "group" add column legacy_url text check (btrim(legacy_url) <> '');

-- Add legacy_url column to event (optional).
alter table event add column legacy_url text check (btrim(legacy_url) <> '');
