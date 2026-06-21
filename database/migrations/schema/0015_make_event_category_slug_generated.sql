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

    -- Ensure generated slugs are unique per alliance before enforcing uniqueness.
    if exists (
        select 1
        from (
            select
                normalized.alliance_id,
                normalized.slug,
                count(*) as total
            from (
                select
                    ec.alliance_id,
                    btrim(regexp_replace(lower(ec.name), '[^\w]+', '-', 'g'), '-') as slug
                from event_category ec
            ) normalized
            group by normalized.alliance_id, normalized.slug
            having count(*) > 1
        ) collisions
    ) then
        raise exception 'event category names generate duplicate slugs in alliance';
    end if;
end;
$$;

alter table event_category
    drop constraint event_category_slug_alliance_id_key,
    drop column slug;

alter table event_category
    add column slug text not null check (btrim(slug) <> '')
        generated always as (
            btrim(regexp_replace(lower(name), '[^\w]+', '-', 'g'), '-')
        ) stored;

alter table event_category
    add constraint event_category_slug_alliance_id_key unique (slug, alliance_id);
