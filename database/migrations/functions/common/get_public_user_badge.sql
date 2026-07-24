-- Returns a durable public badge credential record by opaque award identifier.
create or replace function get_public_user_badge(p_user_badge_id uuid)
returns json as $$
    select json_build_object(
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
        'revocation_reason', ub.revocation_reason,
        'revoked_at', ub.revoked_at,
        'revoked_by_user_id', ub.revoked_by_user_id,
        'user_id', ub.user_id,

        'recipient_name', u.name,
        'recipient_username', u.username
    )
    from user_badge ub
    left join "user" u using (user_id)
    where ub.user_badge_id = p_user_badge_id;
$$ language sql;
