-- Mutes optional notifications from a connected group for a user.
create or replace function mute_user_group_notifications(
    p_actor_user_id uuid,
    p_group_id uuid
)
returns void as $$
declare
    v_group_name text;
begin
    -- Treat groups already muted as a no-op, even if no longer available
    if exists (
        select 1
        from user_group_notification_mute ugm
        where ugm.group_id = p_group_id
        and ugm.user_id = p_actor_user_id
    ) then
        return;
    end if;

    -- Reject groups the user is not connected to or that are unavailable
    if (p_group_id = any(list_user_notification_group_ids(p_actor_user_id))) is not true then
        raise exception 'group not available to mute' using errcode = 'OCG01';
    end if;

    -- Mute the group, leaving a concurrent mute of the same group untouched
    insert into user_group_notification_mute (group_id, user_id)
    values (p_group_id, p_actor_user_id)
    on conflict (user_id, group_id) do nothing;

    -- Audit only mutes inserted by this call
    if found then
        -- Snapshot the group name for the audit trail
        select g.name
        into v_group_name
        from "group" g
        where g.group_id = p_group_id;

        -- Track the mute on the user's own audit trail
        perform insert_audit_log(
            'group_notifications_muted',
            p_actor_user_id,
            'user',
            p_actor_user_id,
            p_details => jsonb_build_object(
                'group_id', p_group_id,
                'group_name', v_group_name
            )
        );
    end if;
end;
$$ language plpgsql;
