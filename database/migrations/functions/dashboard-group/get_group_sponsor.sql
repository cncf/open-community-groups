-- Returns a group sponsor by id.
create or replace function get_group_sponsor(
    p_group_sponsor_id uuid,
    p_group_id uuid
)
returns json as $$
    select json_strip_nulls(json_build_object(
        'group_sponsor_id', gs.group_sponsor_id,
        'logo_url', gs.logo_url,
        'name', gs.name,

        'website_url', gs.website_url
    ))
    from group_sponsor gs
    where gs.group_sponsor_id = p_group_sponsor_id
    and gs.group_id = p_group_id;
$$ language sql;
