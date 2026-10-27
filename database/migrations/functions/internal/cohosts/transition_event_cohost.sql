-- Applies a co-host response transition (approve, reject or cancel) under the event lock.
create or replace function transition_event_cohost(
    p_actor_user_id uuid,
    p_cohost_group_id uuid,
    p_invitation_id uuid,
    p_status text
)
returns json as $$
declare
    v_cohost event_cohost;
    v_event event;
    v_from_status text;
    v_owner_community_id uuid;
begin
    -- Derive the status the transition must start from
    case p_status
        -- Approvals and rejections answer a pending invitation
        when 'approved', 'rejected' then
            v_from_status := 'pending';

        -- Cancellations end an approved co-hosting
        when 'canceled' then
            v_from_status := 'approved';

        -- Reject transitions outside the co-host response lifecycle
        else
            raise exception 'unsupported co-host transition: %', p_status;
    end case;

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

    -- Answer pending invitations only on unpublished, active events
    if v_from_status = 'pending' then
        -- Reject canceled events before answering
        if v_event.canceled then
            raise exception 'event is canceled' using errcode = 'OCG01';
        end if;

        -- Reject answers after publication
        if v_event.published then
            raise exception 'co-hosting can only be approved or rejected before the event is published' using errcode = 'OCG01';
        end if;
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

    -- Reject invitations outside the required starting state
    if v_cohost.event_cohost_status_id <> v_from_status then
        -- Report answers to invitations that are no longer pending
        if v_from_status = 'pending' then
            raise exception 'co-hosting invitation is no longer pending' using errcode = 'OCG01';

        -- Report cancellations of co-hostings that are not approved
        else
            raise exception 'co-hosting is not approved' using errcode = 'OCG01';
        end if;
    end if;

    -- Persist the response, recording approval evidence only on approval
    update event_cohost
    set
        approved_at = case
            -- Record when the co-hosting was approved
            when p_status = 'approved' then current_timestamp
            -- Keep earlier approval evidence on rejection or cancellation
            else approved_at
        end,
        event_cohost_status_id = p_status,
        responded_at = current_timestamp,
        responded_by = p_actor_user_id,
        updated_at = current_timestamp
    where event_id = v_event.event_id
    and group_id = p_cohost_group_id;

    -- Advance the owner editor revision
    update event
    set cohosts_revision = cohosts_revision + 1
    where event_id = v_event.event_id;

    -- Audit the transition for both groups
    perform insert_event_cohost_audit(
        'event_cohost_' || p_status,
        p_actor_user_id,
        v_event.event_id,
        v_event.group_id,
        p_cohost_group_id,
        p_invitation_id,
        v_from_status,
        p_status
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
