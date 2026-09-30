-- Unmutes optional notifications from a group for a user.
create or replace function unmute_user_group_notifications(
    p_actor_user_id uuid,
    p_group_id uuid
)
returns void as $$
declare
    v_group_name text;
begin
    -- Remove the mute whether or not the group is still available
    delete from user_group_notification_mute
    where group_id = p_group_id
    and user_id = p_actor_user_id;

    -- Audit only mutes removed by this call
    if found then
        -- Snapshot the group name for the audit trail
        select g.name
        into v_group_name
        from "group" g
        where g.group_id = p_group_id;

        -- Track the unmute on the user's own audit trail
        perform insert_audit_log(
            'group_notifications_unmuted',
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
