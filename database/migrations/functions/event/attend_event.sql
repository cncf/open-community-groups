-- Attend an event as an attendee.
create or replace function attend_event(
    p_community_id uuid,
    p_event_id uuid,
    p_user_id uuid,
    p_registration_answers jsonb default null,
    p_event_ticket_type_id uuid default null
) returns text as $$
declare
    v_attendee_approval_required boolean;
    v_attendee_count int;
    v_attendee_manually_invited boolean;
    v_attendee_status text;
    v_capacity int;
    v_group_id uuid;
    v_has_registration_questions boolean;
    v_invitation_request_status text;
    v_is_ticketed boolean;
    v_registration_answers jsonb;
    v_registration_ends_at timestamptz;
    v_registration_questions jsonb;
    v_registration_starts_at timestamptz;
    v_registration_window_open boolean;
    v_selectable_public_ticket_count int;
    v_starts_at timestamptz;
    v_ticket_allocated_count int;
    v_ticket_availability text;
    v_ticket_current_price bigint;
    v_ticket_seats_total int;
    v_waitlist_enabled boolean;
begin
    -- Check if event exists in the community, is active and can be attended
    select
        e.attendee_approval_required,
        e.capacity,
        e.group_id,
        exists (
            select 1
            from event_ticket_type ett
            where ett.event_id = e.event_id
        ),
        e.registration_ends_at,
        e.registration_questions,
        e.registration_starts_at,
        e.starts_at,
        e.waitlist_enabled
    into
        v_attendee_approval_required,
        v_capacity,
        v_group_id,
        v_is_ticketed,
        v_registration_ends_at,
        v_registration_questions,
        v_registration_starts_at,
        v_starts_at,
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

    -- Lock ticket tiers before serializing the attendee enrollment boundary
    perform 1
    from event_ticket_type ett
    where ett.event_id = p_event_id
    order by ett.event_ticket_type_id
    for update of ett;

    -- Serialize this attendee's enrollment transitions
    perform pg_advisory_xact_lock(hashtext(p_event_id::text), hashtext(p_user_id::text));

    -- Track question requirements so waitlist joins can skip answer validation
    -- until promotion, while attendee and invitation paths still enforce answers.
    v_has_registration_questions := jsonb_array_length(coalesce(v_registration_questions, '[]'::jsonb)) > 0;
    v_registration_window_open := is_registration_window_open(
        v_registration_starts_at,
        v_registration_ends_at,
        v_starts_at
    );

    -- Lock any existing attendee lifecycle row before selecting the enrollment path
    select
        ea.manually_invited,
        ea.status
    into
        v_attendee_manually_invited,
        v_attendee_status
    from event_attendee ea
    where ea.event_id = p_event_id
    and ea.user_id = p_user_id
    for update of ea;

    -- Reject duplicate confirmed attendance before other enrollment paths
    if v_attendee_status = 'confirmed' then
        raise exception 'user is already attending this event';
    end if;

    -- Claim an owned non-ticketed organizer invitation before direct enrollment
    if complete_non_ticketed_event_admission_offer(
        p_community_id,
        p_event_id,
        p_user_id,
        p_registration_answers
    ) then
        return 'attendee';
    end if;

    -- Convert pending attendee lifecycle states into confirmed attendance
    if v_attendee_status in (
        'invitation-pending',
        'invitation-rejected',
        'registration-questions-pending'
    ) then
        -- Ticketed checkout rows remain pending until purchase completion
        if v_is_ticketed and not coalesce(v_attendee_manually_invited, false) then
            raise exception 'ticketed events must be purchased before attending';
        end if;

        -- Only manual invitation rows can be accepted after public registration closes
        if not coalesce(v_attendee_manually_invited, false)
           and not v_registration_window_open then
            raise exception 'event registration is not open';
        end if;

        -- These lifecycle rows confirm attendance, so validate answers here
        if v_has_registration_questions then
            perform validate_questionnaire_answers_payload(v_registration_questions, p_registration_answers);
            v_registration_answers := p_registration_answers;
        end if;

        -- Preserve the locked attendee row while updating only the status we read
        update event_attendee
        set
            attendance_canceled_at = null,
            attendance_canceled_by_user_id = null,
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

    -- New self-service attendance paths must start while public registration is open
    if not v_registration_window_open then
        raise exception 'event registration is not open';
    end if;

    -- Reject approval requests that conflict with reserved enrollment state
    if v_attendee_approval_required
       and exists (
            select 1
            from admission_offer ao
            where ao.event_id = p_event_id
            and ao.user_id = p_user_id
            and ao.status in ('checkout_pending', 'pending')
            and (ao.expires_at is null or ao.expires_at > current_timestamp)
       ) then
        raise exception 'user already has an active admission offer for this event';
    end if;

    if v_attendee_approval_required
       and exists (
            select 1
            from event_purchase ep
            where ep.event_id = p_event_id
            and ep.user_id = p_user_id
            and ep.status in (
                'completed',
                'pending',
                'refund-pending',
                'refund-recovery-pending',
                'refund-requested'
            )
       ) then
        raise exception 'user already has an active purchase for this event';
    end if;

    -- Route ticketed enrollment into a tier request or a sold-out public queue
    if v_is_ticketed then
        select count(*)::int
        into v_selectable_public_ticket_count
        from event_ticket_type ett
        where ett.event_id = p_event_id
        and ett.active = true
        and ett.availability = 'public'
        and exists (
            select 1
            from event_ticket_price_window etpw
            where etpw.event_ticket_type_id = ett.event_ticket_type_id
            and (etpw.starts_at is null or etpw.starts_at <= current_timestamp)
            and (etpw.ends_at is null or etpw.ends_at >= current_timestamp)
        );

        if v_attendee_approval_required then
            -- Public-tier approval requests retain the attendee's selected tier
            if v_selectable_public_ticket_count > 0 then
                if p_event_ticket_type_id is null then
                    raise exception 'ticket type is required';
                end if;

                perform 1
                from event_ticket_type ett
                where ett.event_id = p_event_id
                and ett.event_ticket_type_id = p_event_ticket_type_id
                and ett.active = true
                and ett.availability = 'public'
                and exists (
                    select 1
                    from event_ticket_price_window etpw
                    where etpw.event_ticket_type_id = ett.event_ticket_type_id
                    and (etpw.starts_at is null or etpw.starts_at <= current_timestamp)
                    and (etpw.ends_at is null or etpw.ends_at >= current_timestamp)
                );

                if not found then
                    raise exception 'ticket type is not publicly available';
                end if;
            elsif p_event_ticket_type_id is not null then
                raise exception 'private ticket requests cannot select a ticket type';
            end if;

            -- Registration answers are collected with ticket approval requests
            if v_has_registration_questions then
                perform validate_questionnaire_answers_payload(
                    v_registration_questions,
                    p_registration_answers
                );
                v_registration_answers := p_registration_answers;
            end if;

            -- Lock any existing invitation request and reject conflicting states
            select eir.status
            into v_invitation_request_status
            from event_invitation_request eir
            where eir.event_id = p_event_id
            and eir.user_id = p_user_id
            for update of eir;

            if v_invitation_request_status = 'pending' then
                raise exception 'user has already requested an invitation for this event';
            end if;

            if v_invitation_request_status = 'rejected' then
                raise exception 'invitation request was rejected for this event';
            end if;

            if v_invitation_request_status = 'accepted' then
                raise exception 'invitation request was already accepted for this event';
            end if;

            -- Create the tier-scoped request for organizer review
            insert into event_invitation_request (
                event_id,
                event_ticket_type_id,
                registration_answers,
                user_id
            ) values (
                p_event_id,
                p_event_ticket_type_id,
                v_registration_answers,
                p_user_id
            );

            return 'pending-approval';
        end if;

        -- Public waitlist joins require a selected, priced, sold-out tier
        if p_event_ticket_type_id is null then
            raise exception 'ticketed events must be purchased before attending';
        end if;

        select
            ett.availability,
            (
                select etpw.amount_minor
                from event_ticket_price_window etpw
                where etpw.event_ticket_type_id = ett.event_ticket_type_id
                and (etpw.starts_at is null or etpw.starts_at <= current_timestamp)
                and (etpw.ends_at is null or etpw.ends_at >= current_timestamp)
                order by
                    etpw.starts_at desc nulls last,
                    etpw.event_ticket_price_window_id
                limit 1
            ),
            ett.seats_total
        into
            v_ticket_availability,
            v_ticket_current_price,
            v_ticket_seats_total
        from event_ticket_type ett
        where ett.event_id = p_event_id
        and ett.event_ticket_type_id = p_event_ticket_type_id
        and ett.active = true;

        if not found
           or v_ticket_availability <> 'public'
           or v_ticket_current_price is null then
            raise exception 'ticket type is not publicly available';
        end if;

        select get_event_ticket_type_allocated_seat_count(
            p_event_id,
            p_event_ticket_type_id
        )
        into v_ticket_allocated_count;

        if v_ticket_allocated_count < v_ticket_seats_total then
            raise exception 'ticket type is still available';
        end if;

        if not v_waitlist_enabled then
            raise exception 'ticket type is sold out';
        end if;

        -- Reject purchase and queue states that block a new waitlist join
        if exists (
            select 1
            from event_purchase ep
            where ep.event_id = p_event_id
            and ep.user_id = p_user_id
            and ep.status in (
                'completed',
                'pending',
                'refund-pending',
                'refund-recovery-pending',
                'refund-requested'
            )
        ) then
            raise exception 'user already has an active purchase for this event';
        end if;

        if exists (
            select 1
            from event_waitlist ew
            where ew.event_id = p_event_id
            and ew.user_id = p_user_id
            and ew.event_ticket_type_id = p_event_ticket_type_id
        ) then
            raise exception 'user is already on the waiting list for this ticket type';
        end if;

        -- Switching ticket queues removes the old position before joining at the back
        delete from event_waitlist
        where event_id = p_event_id
        and user_id = p_user_id;

        delete from event_attendee
        where event_id = p_event_id
        and user_id = p_user_id
        and status in ('attendance-canceled', 'invitation-canceled');

        insert into event_waitlist (
            event_id,
            event_ticket_type_id,
            user_id
        ) values (
            p_event_id,
            p_event_ticket_type_id,
            p_user_id
        );

        return 'waitlisted';
    end if;

    -- Route approval-required events through the invitation request flow
    if v_attendee_approval_required then
        -- Load any existing invitation request for approval-required decisions
        select eir.status into v_invitation_request_status
        from event_invitation_request eir
        where eir.event_id = p_event_id
        and eir.user_id = p_user_id;

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
                    return 'event-capacity-unavailable';
                end if;
            end if;

            -- Recreate the attendee row for an already accepted requester
            insert into event_attendee (event_id, user_id, registration_answers)
            values (p_event_id, p_user_id, v_registration_answers)
            on conflict (event_id, user_id) do update
            set
                attendance_canceled_at = null,
                attendance_canceled_by_user_id = null,
                manually_invited = false,
                registration_answers = v_registration_answers,
                status = 'confirmed'
            where event_attendee.status in ('attendance-canceled', 'invitation-canceled');

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
                -- Remove inactive attendance rows before moving the user into the waitlist
                delete from event_attendee
                where event_id = p_event_id
                and user_id = p_user_id
                and status in ('attendance-canceled', 'invitation-canceled');

                -- Add the user to the waitlist, rejecting duplicate joins below
                insert into event_waitlist (event_id, user_id)
                values (p_event_id, p_user_id)
                on conflict (event_id, user_id) do nothing;

                if not found then
                    raise exception 'user is already on the waiting list for this event';
                end if;

                return 'waitlisted';
            end if;

            return 'event-capacity-unavailable';
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
        attendance_canceled_at = null,
        attendance_canceled_by_user_id = null,
        manually_invited = false,
        registration_answers = v_registration_answers,
        status = 'confirmed'
    where event_attendee.status in (
        'attendance-canceled',
        'invitation-canceled',
        'registration-questions-pending'
    );

    if not found then
        raise exception 'user is already attending this event';
    end if;

    return 'attendee';
end;
$$ language plpgsql;
