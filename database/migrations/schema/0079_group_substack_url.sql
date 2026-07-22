alter table "group"
    add column substack_url text;

alter table "group"
    add constraint group_substack_url_check
        check (btrim(substack_url) <> '');
