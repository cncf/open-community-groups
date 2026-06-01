-- Attend an event as an attendee.
create or replace function attend_event(
    p_community_id uuid,
    p_event_id uuid,
    p_user_id uuid,
    p_registration_answers jsonb default null
) returns text as $$
declare
    v_attendee_approval_required boolean;
    v_attendee_count int;
    v_attendee_status text;
    v_capacity int;
    v_group_id uuid;
    v_has_registration_questions boolean;
    v_invitation_request_status text;
    v_registration_answers jsonb;
    v_registration_questions jsonb;
    v_waitlist_enabled boolean;
begin
    -- Check if event exists in the community, is active and can be attended
    select
        e.attendee_approval_required,
        e.capacity,
        e.group_id,
        e.registration_questions,
        e.waitlist_enabled
    into
        v_attendee_approval_required,
        v_capacity,
        v_group_id,
        v_registration_questions,
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

    -- Track question requirements so waitlist joins can skip answer validation
    -- until promotion, while attendee and invitation paths still enforce answers.
    v_has_registration_questions := jsonb_array_length(coalesce(v_registration_questions, '[]'::jsonb)) > 0;

    -- Lock organizer-created invitation rows before converting them into attendance.
    select ea.status into v_attendee_status
    from event_attendee ea
    where ea.event_id = p_event_id
    and ea.user_id = p_user_id
    and ea.status in ('invitation-pending', 'invitation-rejected', 'registration-questions-pending')
    for update of ea;

    if found then
        -- Invitation acceptance confirms attendance, so validate answers here.
        if v_has_registration_questions then
            perform validate_questionnaire_answers_payload(v_registration_questions, p_registration_answers);
            v_registration_answers := p_registration_answers;
        end if;

        -- Preserve the locked invitation row while updating only the status we read.
        update event_attendee
        set
            registration_answers = v_registration_answers,
            status = 'confirmed'
        where event_id = p_event_id
        and user_id = p_user_id
        and status = v_attendee_status;

        perform insert_audit_log(
            'event_attendee_invitation_accepted',
            p_user_id,
            'user',
            p_user_id,
            p_community_id,
            v_group_id,
            p_event_id,
            jsonb_build_object('event_id', p_event_id, 'user_id', p_user_id)
        );

        return 'attendee';
    end if;

    -- Ensure the user is not already attending
    if exists (
        select 1
        from event_attendee ea
        where ea.event_id = p_event_id
        and ea.user_id = p_user_id
        and ea.status = 'confirmed'
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
        -- Approval requests and accepted-request rejoins are attendee paths,
        -- so required registration answers must be present before proceeding.
        if v_has_registration_questions then
            perform validate_questionnaire_answers_payload(v_registration_questions, p_registration_answers);
            v_registration_answers := p_registration_answers;
        end if;

        -- Existing approved requests can recreate attendance after cancellation
        if v_invitation_request_status = 'accepted' then
            -- Enforce capacity before recreating attendance from an accepted request
            if v_capacity is not null then
                select get_event_occupied_seat_count(p_event_id) into v_attendee_count;

                if v_attendee_count >= v_capacity then
                    raise exception 'event has reached capacity';
                end if;
            end if;

            -- Recreate the attendee row for an already accepted requester
            insert into event_attendee (event_id, user_id, registration_answers)
            values (p_event_id, p_user_id, v_registration_answers)
            on conflict (event_id, user_id) do update
            set
                registration_answers = v_registration_answers,
                status = 'confirmed'
            where event_attendee.status = 'invitation-canceled';

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
        insert into event_invitation_request (event_id, user_id, registration_answers)
        values (p_event_id, p_user_id, v_registration_answers);

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
        select get_event_occupied_seat_count(p_event_id) into v_attendee_count;

        if v_attendee_count >= v_capacity then
            if v_waitlist_enabled then
                -- Remove stale canceled invitations before moving the user into the waitlist
                delete from event_attendee
                where event_id = p_event_id
                and user_id = p_user_id
                and status = 'invitation-canceled';

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

    -- Validate registration answers before creating confirmed attendance
    if v_has_registration_questions then
        perform validate_questionnaire_answers_payload(v_registration_questions, p_registration_answers);
        v_registration_answers := p_registration_answers;
    end if;

    -- Add user as event attendee, reusing canceled organizer invitations
    insert into event_attendee (event_id, user_id, registration_answers)
    values (p_event_id, p_user_id, v_registration_answers)
    on conflict (event_id, user_id) do update
    set
        registration_answers = v_registration_answers,
        status = 'confirmed'
    where event_attendee.status in ('invitation-canceled', 'registration-questions-pending');

    if not found then
        raise exception 'user is already attending this event';
    end if;

    return 'attendee';
end;
$$ language plpgsql;
