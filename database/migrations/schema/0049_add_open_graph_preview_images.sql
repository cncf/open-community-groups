-- Apply safely to both the pre-baseline production schema and fresh baseline databases.
alter table "group"
    add column if not exists og_image_url text check (btrim(og_image_url) <> '');

create index if not exists alliance_og_image_url_idx on alliance (og_image_url)
where og_image_url is not null;

create index if not exists group_og_image_url_idx on "group" (og_image_url)
where og_image_url is not null;
