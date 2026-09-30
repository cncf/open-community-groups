-- Returns a user's notification category opt-outs and muted groups.
create or replace function get_user_notification_preferences(p_user_id uuid)
returns json as $$
    select json_build_object(
        'muted_groups', (
            select coalesce(
                json_agg(
                    json_strip_nulls(json_build_object(
                        'available', (
                            c.active = true
                            and g.active = true
                            and g.deleted = false
                        ),
                        'community_display_name', c.display_name,
                        'group_id', g.group_id,
                        'muted_at', epoch_seconds(ugm.created_at),
                        'name', g.name,

                        'logo_url', g.logo_url
                    ))
                    order by g.name asc, g.group_id asc
                ),
                '[]'::json
            )
            from user_group_notification_mute ugm
            join "group" g using (group_id)
            join community c on c.community_id = g.community_id
            where ugm.user_id = p_user_id
        ),
        'opted_out_categories', (
            select coalesce(
                json_agg(uo.notification_category_id order by uo.notification_category_id),
                '[]'::json
            )
            from user_notification_opt_out uo
            where uo.user_id = p_user_id
        )
    );
$$ language sql;
