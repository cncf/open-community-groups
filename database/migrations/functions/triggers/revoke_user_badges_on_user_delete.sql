-- Revokes active credentials before their recipient association is removed.
create or replace function revoke_user_badges_on_user_delete()
returns trigger as $$
begin
    -- Revoke every active award before the user foreign key is cleared
    with revoked as (
        update user_badge
        set
            is_listed = false,
            revocation_reason = 'recipient account deleted',
            revoked_at = current_timestamp,
            revoked_by_user_id = null
        where user_id = old.user_id
        and revoked_at is null
        returning event_id, group_id, snapshot, user_badge_id
    )
    insert into audit_log (
        action,
        actor_username,
        community_id,
        details,
        event_id,
        group_id,
        resource_id,
        resource_type
    )
    select
        'badge_revoked_account_deleted',
        old.username,
        g.community_id,
        jsonb_build_object(
            'badge_name', revoked.snapshot->>'name',
            'reason', 'recipient account deleted'
        ),
        revoked.event_id,
        revoked.group_id,
        revoked.user_badge_id,
        'user_badge'
    from revoked
    join "group" g using (group_id);

    -- Continue the user deletion
    return old;
end;
$$ language plpgsql;
