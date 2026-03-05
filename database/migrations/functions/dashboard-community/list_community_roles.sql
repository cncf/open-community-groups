-- list_community_roles returns all available community roles.
create or replace function list_community_roles()
returns json as $$
    select coalesce(
        json_agg(
            json_build_object(
                'community_role_id', cr.community_role_id,
                'display_name', cr.display_name
            )
            order by cr.community_role_id
        ),
        '[]'
    )
    from community_role cr;
$$ language sql;
