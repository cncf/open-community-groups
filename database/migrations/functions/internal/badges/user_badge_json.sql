-- Projects a badge award row into the base JSON read by the Rust UserBadge
-- type, including the identity binding fields only when requested. Callers
-- append the event and recipient context they resolve.
create or replace function user_badge_json(
    p_user_badge user_badge,
    p_include_identity boolean
)
returns jsonb as $$
    select jsonb_build_object(
        'awarded_at', p_user_badge.awarded_at,
        'badge_status_list_id', p_user_badge.badge_status_list_id,
        'display_order', p_user_badge.display_order,
        'group_id', p_user_badge.group_id,
        'is_listed', p_user_badge.is_listed,
        'snapshot', p_user_badge.snapshot,
        'status_list_index', p_user_badge.status_list_index,
        'user_badge_id', p_user_badge.user_badge_id,

        'badge_id', p_user_badge.badge_id,
        'event_id', p_user_badge.event_id,
        'revocation_reason', p_user_badge.revocation_reason,
        'revoked_at', p_user_badge.revoked_at,
        'revoked_by_user_id', p_user_badge.revoked_by_user_id,
        'user_id', p_user_badge.user_id
    )
    || case
        -- Include the recipient email identity binding when requested
        when p_include_identity then jsonb_build_object(
            'identity_bound_at', p_user_badge.identity_bound_at,
            'identity_hash', p_user_badge.identity_hash,
            'identity_salt', p_user_badge.identity_salt
        )
        -- Omit the identity binding keys otherwise
        else '{}'::jsonb
    end;
$$ language sql stable;
