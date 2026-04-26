-- Accepts an event invitation request and creates a confirmed attendee row.
create or replace function accept_event_invitation_request(
    p_actor_user_id uuid,
    p_group_id uuid,
    p_event_id uuid,
    p_user_id uuid
)
returns void as $$
declare
    v_attendee_count int;
    v_capacity int;
    v_community_id uuid;
begin
    -- Lock the event and verify it belongs to the selected group
    select
        e.capacity,
        g.community_id
    into
        v_capacity,
        v_community_id
    from event e
    join "group" g on g.group_id = e.group_id
    where e.event_id = p_event_id
    and e.group_id = p_group_id
    and g.active = true
    and e.attendee_approval_required = true
    and e.deleted = false
    and e.published = true
    and e.canceled = false
    and (
        coalesce(e.ends_at, e.starts_at) is null
        or coalesce(e.ends_at, e.starts_at) >= current_timestamp
    )
    for update of e;

    if not found then
        raise exception 'event not found or inactive';
    end if;

    -- Ensure the request is still pending before accepting it
    if not exists (
        select 1
        from event_invitation_request eir
        where eir.event_id = p_event_id
        and eir.user_id = p_user_id
        and eir.status = 'pending'
    ) then
        raise exception 'pending invitation request not found';
    end if;

    -- Enforce event capacity against already accepted attendees
    if v_capacity is not null then
        select count(*) into v_attendee_count
        from event_attendee
        where event_id = p_event_id;

        if v_attendee_count >= v_capacity then
            raise exception 'event has reached capacity';
        end if;
    end if;

    -- Mark the request accepted and create the confirmed attendee
    update event_invitation_request
    set
        reviewed_at = current_timestamp,
        reviewed_by = p_actor_user_id,
        status = 'accepted'
    where event_id = p_event_id
    and user_id = p_user_id
    and status = 'pending';

    insert into event_attendee (event_id, user_id)
    values (p_event_id, p_user_id)
    on conflict (event_id, user_id) do nothing;

    -- Track the organizer decision
    perform insert_audit_log(
        'event_invitation_request_accepted',
        p_actor_user_id,
        'user',
        p_user_id,
        v_community_id,
        p_group_id,
        p_event_id,
        jsonb_build_object('event_id', p_event_id, 'user_id', p_user_id)
    );
end;
$$ language plpgsql;
