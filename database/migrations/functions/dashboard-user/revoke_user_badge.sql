-- Permanently revokes a badge owned by a dashboard user.
create or replace function revoke_user_badge(p_actor_user_id uuid, p_user_badge_id uuid)
returns void as $$
declare
    v_community_id uuid;
    v_user_badge user_badge%rowtype;
begin
    -- Serialize this user's active badge order before locking the award
    perform 1
    from "user"
    where user_id = p_actor_user_id
    for update;

    if not found then
        raise exception 'awarded badge not found';
    end if;

    -- Lock and validate current ownership before changing credential state
    select ub.*
    into v_user_badge
    from user_badge ub
    where ub.user_badge_id = p_user_badge_id
    and ub.user_id = p_actor_user_id
    for update;

    if not found then
        raise exception 'awarded badge not found';
    end if;
    if v_user_badge.revoked_at is not null then
        return;
    end if;

    -- Persist the irreversible self-revocation without notifying the actor
    update user_badge
    set
        is_listed = false,
        revocation_reason = 'recipient revoked badge',
        revoked_at = current_timestamp,
        revoked_by_user_id = p_actor_user_id
    where user_badge_id = p_user_badge_id
    returning * into v_user_badge;

    -- Resolve the retained community parent for lifecycle auditing
    select community_id
    into v_community_id
    from "group"
    where group_id = v_user_badge.group_id;

    perform insert_audit_log(
        'badge_revoked_by_recipient',
        p_actor_user_id,
        'user_badge',
        p_user_badge_id,
        v_community_id,
        v_user_badge.group_id,
        v_user_badge.event_id,
        jsonb_build_object('badge_name', v_user_badge.snapshot->>'name')
    );
end;
$$ language plpgsql;
