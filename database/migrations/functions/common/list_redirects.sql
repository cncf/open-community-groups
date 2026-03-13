-- Returns all unique normalized redirect mappings with canonical relative paths.
create or replace function list_redirects()
returns table (
    legacy_path text,
    new_path text
) as $$
    with redirect_candidates as (
        -- Load active group redirect targets
        select
            coalesce(
                nullif(
                    trim(
                        trailing '/'
                        from regexp_replace(split_part(g.legacy_url, '?', 1), '^https?://[^/]+', '')
                    ),
                    ''
                ),
                '/'
            ) as legacy_path,

            format('/%s/group/%s',
                c.name,
                g.slug
            ) as new_path
        from "group" g
        join community c using (community_id)
        where c.active = true
          and g.active = true
          and g.legacy_url is not null

        union all

        -- Load published event redirect targets
        select
            coalesce(
                nullif(
                    trim(
                        trailing '/'
                        from regexp_replace(split_part(e.legacy_url, '?', 1), '^https?://[^/]+', '')
                    ),
                    ''
                ),
                '/'
            ) as legacy_path,

            format('/%s/group/%s/event/%s',
                c.name,
                g.slug,
                e.slug
            ) as new_path
        from event e
        join "group" g using (group_id)
        join community c using (community_id)
        where c.active = true
          and g.active = true
          and e.published = true
          and e.legacy_url is not null
    )
    -- Keep only unique normalized legacy paths
    select
        legacy_path,
        min(new_path) as new_path
    from redirect_candidates
    group by legacy_path
    having count(*) = 1
    order by legacy_path;
$$ language sql stable;
