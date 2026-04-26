-- Attend an event as an attendee.
create or replace function attend_event(
    p_community_id uuid,
    p_event_id uuid,
    p_user_id uuid
) returns text as $$
declare
    v_attendee_approval_required boolean;
    v_attendee_count int;
    v_capacity int;
    v_invitation_request_status text;
    v_waitlist_enabled boolean;
begin
    -- Check if event exists in the community, is active and can be attended
    select
        e.attendee_approval_required,
        e.capacity,
        e.waitlist_enabled
    into
        v_attendee_approval_required,
        v_capacity,
        v_waitlist_enabled
    from event e
    join "group" g on g.group_id = e.group_id
    where e.event_id = p_event_id
    and g.community_id = p_community_id
    and g.active = true
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

    -- Ensure the user is not already attending or waitlisted
    if exists (
        select 1
        from event_attendee ea
        where ea.event_id = p_event_id
        and ea.user_id = p_user_id
    ) then
        raise exception 'user is already attending this event';
    end if;

    -- Load any existing invitation request for approval-required decisions
    select eir.status into v_invitation_request_status
    from event_invitation_request eir
    where eir.event_id = p_event_id
    and eir.user_id = p_user_id;

    -- Route approval-required events through the invitation request flow
    if v_attendee_approval_required then
        -- Existing approved requests can recreate attendance after cancellation
        if v_invitation_request_status = 'accepted' then
            -- Enforce capacity before recreating attendance from an accepted request
            if v_capacity is not null then
                select count(*) into v_attendee_count
                from event_attendee
                where event_id = p_event_id;

                if v_attendee_count >= v_capacity then
                    raise exception 'event has reached capacity';
                end if;
            end if;

            -- Recreate the attendee row for an already accepted requester
            insert into event_attendee (event_id, user_id)
            values (p_event_id, p_user_id)
            on conflict (event_id, user_id) do nothing;

            return 'attendee';
        end if;

        -- Prevent duplicate pending requests from being created
        if v_invitation_request_status = 'pending' then
            raise exception 'user has already requested an invitation for this event';
        end if;

        -- Prevent rejected users from resubmitting an invitation request
        if v_invitation_request_status = 'rejected' then
            raise exception 'invitation request was rejected for this event';
        end if;

        -- Create a new request instead of confirming attendance immediately
        insert into event_invitation_request (event_id, user_id)
        values (p_event_id, p_user_id);

        return 'pending-approval';
    end if;

    -- Ensure the user is not already waitlisted before normal RSVP flow
    if exists (
        select 1
        from event_waitlist ew
        where ew.event_id = p_event_id
        and ew.user_id = p_user_id
    ) then
        raise exception 'user is already on the waiting list for this event';
    end if;

    -- Check if event has capacity for more attendees
    if v_capacity is not null then
        select count(*) into v_attendee_count
        from event_attendee
        where event_id = p_event_id;

        if v_attendee_count >= v_capacity then
            if v_waitlist_enabled then
                begin
                    insert into event_waitlist (event_id, user_id)
                    values (p_event_id, p_user_id);
                exception when unique_violation then
                    raise exception 'user is already on the waiting list for this event';
                end;

                return 'waitlisted';
            end if;

            raise exception 'event has reached capacity';
        end if;
    end if;

    -- Add user as event attendee
    begin
        insert into event_attendee (event_id, user_id)
        values (p_event_id, p_user_id);
    exception when unique_violation then
        raise exception 'user is already attending this event';
    end;

    return 'attendee';
end;
$$ language plpgsql;
