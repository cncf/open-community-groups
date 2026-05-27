-- Add optional Open Graph image support for public group previews.
alter table "group"
add column og_image_url text check (btrim(og_image_url) <> '');

-- Speed up public Open Graph image authorization for community previews.
create index community_og_image_url_idx on community (og_image_url)
where og_image_url is not null;

-- Speed up public Open Graph image authorization for group and event previews.
create index group_og_image_url_idx on "group" (og_image_url)
where og_image_url is not null;
