-- list_alliance_roles returns all available alliance roles.
create or replace function list_alliance_roles()
returns json as $$
    select coalesce(
        json_agg(
            json_build_object(
                'alliance_role_id', cr.alliance_role_id,
                'display_name', cr.display_name
            )
            order by cr.alliance_role_id
        ),
        '[]'
    )
    from alliance_role cr;
$$ language sql;
