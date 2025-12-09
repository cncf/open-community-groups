-- Auto-generate slugs for groups and events

-- Generates random alphanumeric codes for use as slugs.
create or replace function generate_slug(p_length int default 7)
returns text language sql as $$
    select string_agg(
        substr('23456789abcdefghjkmnpqrstuvwxyz', floor(random() * 31 + 1)::int, 1),
        ''
    )
    from generate_series(1, p_length)
$$;

-- Remove slug from group tsdoc.
alter table "group" drop column tsdoc;
alter table "group" add column tsdoc tsvector not null
    generated always as (
        setweight(to_tsvector('simple', name), 'A') ||
        setweight(to_tsvector('simple', i_array_to_string(coalesce(tags, '{}'), ' ')), 'B') ||
        setweight(to_tsvector('simple', coalesce(city, '')), 'C') ||
        setweight(to_tsvector('simple', coalesce(state, '')), 'C') ||
        setweight(to_tsvector('simple', coalesce(country_name, '')), 'C')
    ) stored;
create index group_tsdoc_idx on "group" using gin (tsdoc);

-- Remove slug from event tsdoc.
alter table event drop column tsdoc;
alter table event add column tsdoc tsvector not null
    generated always as (
        setweight(to_tsvector('simple', name), 'A') ||
        setweight(to_tsvector('simple', i_array_to_string(coalesce(tags, '{}'), ' ')), 'B') ||
        setweight(to_tsvector('simple', coalesce(venue_name, '')), 'C') ||
        setweight(to_tsvector('simple', coalesce(venue_city, '')), 'C')
    ) stored;
create index event_tsdoc_idx on event using gin (tsdoc);

-- Migrate existing group slugs to new format (one at a time to handle collisions).
do $$
declare
    v_group record;
    v_new_slug text;
    v_collision boolean;
begin
    for v_group in select group_id, community_id from "group" loop
        v_collision := true;
        while v_collision loop
            v_new_slug := generate_slug(7);
            v_collision := exists (
                select 1 from "group"
                where slug = v_new_slug
                and community_id = v_group.community_id
                and group_id != v_group.group_id
            );
        end loop;
        update "group" set slug = v_new_slug where group_id = v_group.group_id;
    end loop;
end $$;

-- Migrate existing event slugs to new format (one at a time to handle collisions).
do $$
declare
    v_event record;
    v_new_slug text;
    v_collision boolean;
begin
    for v_event in select event_id, group_id from event loop
        v_collision := true;
        while v_collision loop
            v_new_slug := generate_slug(7);
            v_collision := exists (
                select 1 from event
                where slug = v_new_slug
                and group_id = v_event.group_id
                and event_id != v_event.event_id
            );
        end loop;
        update event set slug = v_new_slug where event_id = v_event.event_id;
    end loop;
end $$;
