-- Inserts owner and co-host scoped audit rows for a co-host transition.
create or replace function insert_event_cohost_audit(
    p_action text,
    p_actor_user_id uuid,
    p_event_id uuid,
    p_owner_group_id uuid,
    p_cohost_group_id uuid,
    p_invitation_id uuid,
    p_from_status text,
    p_to_status text
)
returns void as $$
declare
    v_cohost_community_id uuid;
    v_details jsonb;
    v_owner_community_id uuid;
begin
    -- Resolve the owner and co-host audit scopes
    select community_id
    into v_owner_community_id
    from "group"
    where group_id = p_owner_group_id;

    select community_id
    into v_cohost_community_id
    from "group"
    where group_id = p_cohost_group_id;

    -- Build shared transition details
    v_details := jsonb_build_object(
        'cohost_group_id', p_cohost_group_id,
        'from_status', p_from_status,
        'invitation_id', p_invitation_id,
        'owner_group_id', p_owner_group_id,
        'to_status', p_to_status
    );

    -- Store the owner-scoped audit row
    perform insert_audit_log(
        p_action,
        p_actor_user_id,
        'event',
        p_event_id,
        v_owner_community_id,
        p_owner_group_id,
        p_event_id,
        v_details
    );

    -- Store the co-host-scoped audit row
    perform insert_audit_log(
        p_action,
        p_actor_user_id,
        'event',
        p_event_id,
        v_cohost_community_id,
        p_cohost_group_id,
        p_event_id,
        v_details
    );
end;
$$ language plpgsql;
