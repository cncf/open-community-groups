-- Returns redirect target data for a unique legacy path match.
-- Returns null when there is no match or when multiple matches exist.
create or replace function get_redirect_target(p_entity text, p_legacy_path text)
returns json as $$
declare
    v_legacy_path text := coalesce(nullif(trim(trailing '/' from p_legacy_path), ''), '/');
    v_redirect_target json;
begin
    if p_entity = 'event' then
        -- Match event legacy URLs by their extracted path
        select
            case
                when count(*) = 1 then json_build_object(
                    'community_name', min(community_name),
                    'entity', 'event',
                    'group_slug', min(group_slug),
                    'event_slug', min(event_slug)
                )
                else null
            end
        into v_redirect_target
        from (
            select
                c.name as community_name,
                g.slug as group_slug,
                e.slug as event_slug
            from event e
            join "group" g using (group_id)
            join community c using (community_id)
            where c.active = true
              and g.active = true
              and e.published = true
              and e.legacy_url is not null
              and coalesce(
                    nullif(
                        trim(
                            trailing '/'
                            from regexp_replace(split_part(e.legacy_url, '?', 1), '^https?://[^/]+', '')
                        ),
                        ''
                    ),
                    '/'
                ) = v_legacy_path
            limit 2
        ) matches;
    elsif p_entity = 'group' then
        -- Match group legacy URLs by their extracted path
        select
            case
                when count(*) = 1 then json_build_object(
                    'community_name', min(community_name),
                    'entity', 'group',
                    'group_slug', min(group_slug),
                    'event_slug', null
                )
                else null
            end
        into v_redirect_target
        from (
            select
                c.name as community_name,
                g.slug as group_slug
            from "group" g
            join community c using (community_id)
            where c.active = true
              and g.active = true
              and g.legacy_url is not null
              and coalesce(
                    nullif(
                        trim(
                            trailing '/'
                            from regexp_replace(split_part(g.legacy_url, '?', 1), '^https?://[^/]+', '')
                        ),
                        ''
                    ),
                    '/'
                ) = v_legacy_path
            limit 2
        ) matches;
    else
        raise exception 'invalid redirect entity: %', p_entity;
    end if;

    return v_redirect_target;
end;
$$ language plpgsql;
