-- Lists active groups that can be selected as co-hosts within a community.
create or replace function list_cohost_group_options(
    p_community_id uuid,
    p_exclude_group_id uuid
)
returns json as $$
    select coalesce(
        json_agg(
            jsonb_strip_nulls(jsonb_build_object(
                'community_display_name', c.display_name,
                'community_name', c.name,
                'group_id', g.group_id,
                'logo_url', coalesce(g.logo_url, c.logo_url),
                'name', g.name,
                'slug', g.slug,

                'slug_pretty', g.slug_pretty
            ))
            order by g.name asc, g.group_id asc
        ),
        '[]'::json
    )
    from "group" g
    join community c using (community_id)
    where c.community_id = p_community_id
    and c.active = true
    and g.active = true
    and g.deleted = false
    and g.group_id <> p_exclude_group_id;
$$ language sql stable;
