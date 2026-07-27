-- Permanently revokes a group-issued badge and notifies its recipient.
create or replace function revoke_group_user_badge(
    p_actor_user_id uuid,
    p_community_id uuid,
    p_group_id uuid,
    p_user_badge_id uuid,
    p_reason text
)
returns void as $$
declare
    v_reason text;
    v_recipient_user_id uuid;
    v_theme jsonb;
    v_user_badge user_badge%rowtype;
begin
    -- Authorize the actor and normalize the private audit reason
    if not user_has_group_permission(
        p_community_id,
        p_group_id,
        p_actor_user_id,
        'group.badges.write'
    ) then
        raise exception 'badge permission denied' using errcode = 'insufficient_privilege';
    end if;
    v_reason := nullif(btrim(p_reason), '');
    if v_reason is null then
        raise exception 'badge revocation reason is required';
    end if;

    -- Resolve and lock the recipient before the award to preserve lock order
    select user_id
    into v_recipient_user_id
    from user_badge
    where user_badge_id = p_user_badge_id
    and group_id = p_group_id;

    if not found then
        raise exception 'awarded badge not found';
    end if;
    if v_recipient_user_id is not null then
        perform 1
        from "user"
        where user_id = v_recipient_user_id
        for update;
    end if;

    -- Lock and recheck the award ownership before its terminal transition
    select *
    into v_user_badge
    from user_badge
    where user_badge_id = p_user_badge_id
    and group_id = p_group_id
    for update;

    if not found then
        raise exception 'awarded badge not found';
    end if;
    if v_user_badge.revoked_at is not null then
        return;
    end if;

    -- Persist the irreversible revocation and remove profile discovery
    update user_badge
    set
        is_listed = false,
        revocation_reason = v_reason,
        revoked_at = current_timestamp,
        revoked_by_user_id = p_actor_user_id
    where user_badge_id = p_user_badge_id
    returning * into v_user_badge;
    select theme into v_theme from site limit 1;

    -- Enqueue the recipient notification inside the same database operation
    perform enqueue_notification(
        'badge-revoked',
        jsonb_build_object(
            'badge_name', v_user_badge.snapshot->>'name',
            'dashboard_url', '/dashboard/user?tab=badges',
            'group_name', v_user_badge.snapshot->'issuer'->>'group_name',
            'theme', v_theme
        ),
        '[]'::jsonb,
        array[v_user_badge.user_id]
    );

    -- Record the actor and private reason only after the transition succeeds
    perform insert_audit_log(
        'badge_revoked',
        p_actor_user_id,
        'user_badge',
        p_user_badge_id,
        p_community_id,
        p_group_id,
        v_user_badge.event_id,
        jsonb_build_object(
            'badge_name', v_user_badge.snapshot->>'name',
            'reason', v_reason
        )
    );
end;
$$ language plpgsql;
