-- Make event category slug generated from category name.
do $$
begin
    -- Ensure existing names can be normalized into non-empty generated slugs.
    if exists (
        select 1
        from event_category ec
        where btrim(regexp_replace(lower(ec.name), '[^\w]+', '-', 'g'), '-') = ''
    ) then
        raise exception 'event category name generates empty slug';
    end if;

    -- Ensure generated slugs are unique per community before enforcing uniqueness.
    if exists (
        select 1
        from (
            select
                normalized.community_id,
                normalized.slug,
                count(*) as total
            from (
                select
                    ec.community_id,
                    btrim(regexp_replace(lower(ec.name), '[^\w]+', '-', 'g'), '-') as slug
                from event_category ec
            ) normalized
            group by normalized.community_id, normalized.slug
            having count(*) > 1
        ) collisions
    ) then
        raise exception 'event category names generate duplicate slugs in community';
    end if;
end;
$$;

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
