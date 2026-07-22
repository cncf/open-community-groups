alter table "group"
    add column google_photos_url text;

alter table "group"
    add constraint group_google_photos_url_check
        check (btrim(google_photos_url) <> '');
