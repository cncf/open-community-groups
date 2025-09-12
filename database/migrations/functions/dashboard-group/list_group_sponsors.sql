-- Returns all sponsors for a given group.
create or replace function list_group_sponsors(p_group_id uuid)
returns json as $$
    select coalesce(
        json_agg(
            json_strip_nulls(json_build_object(
                'group_sponsor_id', gs.group_sponsor_id,
                'logo_url', gs.logo_url,
                'name', gs.name,

                'website_url', gs.website_url
            )) order by gs.name
        ), '[]'::json
    )
    from group_sponsor gs
    where gs.group_id = p_group_id;
$$ language sql;
