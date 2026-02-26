-- Make event category slug generated from category name.
alter table event_category
    drop constraint event_category_slug_community_id_key,
    drop column slug;

alter table event_category
    add column slug text not null check (btrim(slug) <> '')
        generated always as (
            btrim(regexp_replace(lower(name), '[^\w]+', '-', 'g'), '-')
        ) stored;

alter table event_category
    add constraint event_category_slug_community_id_key unique (slug, community_id);
