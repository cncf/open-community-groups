alter table "group"
    add column if not exists substack_url text;

alter table "group"
    drop constraint if exists group_substack_url_check,
    add constraint group_substack_url_check
        check (btrim(substack_url) <> '');
