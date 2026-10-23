-- Returns all unique normalized redirect mappings with canonical relative paths.
create or replace function list_redirects()
returns table (
    community_name text,
    legacy_path text,
    new_path text
) as $$
    with redirect_candidates as (
        -- Load public group redirect targets
        select
            c.name as community_name,
            g.legacy_url,
            format('/%s/group/%s',
                c.name,
                g.slug
            ) as new_path
        from "group" g
        join community c using (community_id)
        where c.active = true
          and is_group_public(g)
          and g.legacy_url is not null

        union all

        -- Load public event redirect targets
        select
            c.name as community_name,
            e.legacy_url,
            format('/%s/group/%s/event/%s',
                c.name,
                g.slug,
                e.slug
            ) as new_path
        from event e
        join "group" g using (group_id)
        join community c using (community_id)
        where c.active = true
          and is_event_public(e, g)
          and e.legacy_url is not null
    ),
    normalized_candidates as (
        -- Normalize legacy URLs to relative paths without query or trailing slash
        select
            community_name,
            coalesce(
                nullif(
                    trim(
                        trailing '/'
                        from regexp_replace(split_part(legacy_url, '?', 1), '^https?://[^/]+', '')
                    ),
                    ''
                ),
                '/'
            ) as legacy_path,
            new_path
        from redirect_candidates
    )
    -- Keep only unique normalized legacy paths within each community
    select
        community_name,
        legacy_path,
        min(new_path) as new_path
    from normalized_candidates
    group by community_name, legacy_path
    having count(*) = 1
    order by community_name, legacy_path;
$$ language sql stable;
