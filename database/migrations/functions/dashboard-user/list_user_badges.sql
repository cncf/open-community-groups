-- Lists active badges owned by a dashboard user.
create or replace function list_user_badges(p_user_id uuid)
returns json as $$
    select coalesce(
        json_agg(
            json_build_object(
                'awarded_at', ub.awarded_at,
                'badge_status_list_id', ub.badge_status_list_id,
                'display_order', ub.display_order,
                'group_id', ub.group_id,
                'is_listed', ub.is_listed,
                'snapshot', ub.snapshot,
                'status_list_index', ub.status_list_index,
                'user_badge_id', ub.user_badge_id,

                'badge_id', ub.badge_id,
                'event_id', ub.event_id,
                'event_name', null,
                'recipient_name', null,
                'recipient_username', null,
                'revocation_reason', ub.revocation_reason,
                'revoked_at', ub.revoked_at,
                'revoked_by_user_id', ub.revoked_by_user_id,
                'user_id', ub.user_id
            )
            order by ub.display_order, ub.awarded_at desc, ub.user_badge_id
        ),
        '[]'::json
    )
    from user_badge ub
    where ub.user_id = p_user_id
    and ub.revoked_at is null;
$$ language sql;
