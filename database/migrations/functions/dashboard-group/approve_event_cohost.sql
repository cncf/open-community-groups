-- Approves a pending event co-host invitation.
create or replace function approve_event_cohost(
    p_actor_user_id uuid,
    p_cohost_group_id uuid,
    p_invitation_id uuid
)
returns json as $$
declare
    v_cohost event_cohost;
    v_event event;
    v_owner_community_id uuid;
begin
    -- Resolve the invitation target before taking event locks
    select event_id
    into v_event.event_id
    from event_cohost
    where group_id = p_cohost_group_id
    and invitation_id = p_invitation_id;

    -- Reject missing or stale invitations
    if not found then
        raise exception 'co-hosting invitation not found' using errcode = 'OCG01';
    end if;

    -- Lock the event that owns this invitation
    select e.*
    into v_event
    from event e
    where e.event_id = v_event.event_id
    and e.deleted = false
    for update of e;

    -- Reject deleted events as stale invitations
    if not found then
        raise exception 'co-hosting invitation not found' using errcode = 'OCG01';
    end if;

    -- Reject canceled events before approval
    if v_event.canceled then
        raise exception 'event is canceled' using errcode = 'OCG01';
    end if;

    -- Reject approvals after publication
    if v_event.published then
        raise exception 'co-hosting can only be approved or rejected before the event is published' using errcode = 'OCG01';
    end if;

    -- Lock and verify the invitation row
    select ec.*
    into v_cohost
    from event_cohost ec
    where ec.event_id = v_event.event_id
    and ec.group_id = p_cohost_group_id
    and ec.invitation_id = p_invitation_id
    for update of ec;

    -- Reject rotated or missing invitations
    if not found then
        raise exception 'co-hosting invitation not found' using errcode = 'OCG01';
    end if;

    -- Reject invitations outside the pending state
    if v_cohost.event_cohost_status_id <> 'pending' then
        raise exception 'co-hosting invitation is no longer pending' using errcode = 'OCG01';
    end if;

    -- Persist approval evidence
    update event_cohost
    set
        approved_at = current_timestamp,
        event_cohost_status_id = 'approved',
        responded_at = current_timestamp,
        responded_by = p_actor_user_id,
        updated_at = current_timestamp
    where event_id = v_event.event_id
    and group_id = p_cohost_group_id;

    -- Advance the owner editor revision
    update event
    set cohosts_revision = cohosts_revision + 1
    where event_id = v_event.event_id;

    -- Audit the approved transition for both groups
    perform insert_event_cohost_audit(
        'event_cohost_approved',
        p_actor_user_id,
        v_event.event_id,
        v_event.group_id,
        p_cohost_group_id,
        p_invitation_id,
        'pending',
        'approved'
    );

    -- Resolve the owner community for the response contract
    select community_id
    into v_owner_community_id
    from "group"
    where group_id = v_event.group_id;

    -- Return identifiers needed for owner notifications
    return json_build_object(
        'cohost_group_id', p_cohost_group_id,
        'event_id', v_event.event_id,
        'invitation_id', p_invitation_id,
        'owner_community_id', v_owner_community_id,
        'owner_group_id', v_event.group_id
    );
end;
$$ language plpgsql;
