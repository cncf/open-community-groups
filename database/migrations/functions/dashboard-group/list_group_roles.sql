-- list_group_roles returns all available group roles.
create or replace function list_group_roles()
returns json as $$
    select coalesce(
        json_agg(
            json_build_object(
                'group_role_id', gr.group_role_id,
                'display_name', gr.display_name
            )
            order by gr.group_role_id
        ),
        '[]'
    )
    from group_role gr;
$$ language sql;

