-- Lists the connected groups a user can mute, excluding groups already muted.
create or replace function list_user_notification_group_options(p_user_id uuid)
returns json as $$
    select coalesce(
        json_agg(
            json_strip_nulls(json_build_object(
                'community_display_name', c.display_name,
                'group_id', g.group_id,
                'name', g.name,

                'logo_url', g.logo_url
            ))
            order by g.name asc, g.group_id asc
        ),
        '[]'::json
    )
    from "group" g
    join community c on c.community_id = g.community_id
    where g.group_id = any(list_user_notification_group_ids(p_user_id))
    and not exists (
        select 1
        from user_group_notification_mute ugm
        where ugm.group_id = g.group_id
        and ugm.user_id = p_user_id
    );
$$ language sql;
