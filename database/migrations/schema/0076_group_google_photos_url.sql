alter table "group"
    add column if not exists google_photos_url text;

alter table "group"
    drop constraint if exists group_google_photos_url_check,
    add constraint group_google_photos_url_check
        check (btrim(google_photos_url) <> '');
