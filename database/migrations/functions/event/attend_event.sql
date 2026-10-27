-- Routes an attendee into checkout, approval, or a tier-scoped waitlist.
create or replace function attend_event(
    p_community_id uuid,
    p_event_id uuid,
    p_user_id uuid,
    p_registration_answers jsonb default null,
    p_event_ticket_type_id uuid default null
) returns text as $$
declare
    v_allows_free_hold_reuse boolean;
    v_event event;
    v_has_blocking_purchase boolean;
    v_has_registration_questions boolean;
    v_has_reusable_free_purchase boolean;
    v_invitation_request_status text;
    v_resolved_ticket_type_id uuid;
    v_selectable_public_ticket_count int;
    v_ticket_allocated_count int;
    v_ticket_seats_total int;
begin
    -- Lock and validate the attendee-visible event
    v_event := lock_active_event(p_community_id, null, p_event_id);

    -- Reconcile stale reservations under the global lock order, serializing this attendee
    perform reconcile_event_enrollment(p_event_id, null, null, p_user_id);

    -- Require public registration for every new self-service enrollment
    if not is_registration_window_open(
        v_event.registration_starts_at,
        v_event.registration_ends_at,
        v_event.starts_at
    ) then
        raise exception 'event registration is not open' using errcode = 'OCG01';
    end if;

    -- Reject attendees that are already enrolled
    if exists (
        select 1
        from event_attendee ea
        where ea.event_id = p_event_id
        and ea.user_id = p_user_id
        and ea.status = 'confirmed'
    ) then
        raise exception 'user is already attending this event' using errcode = 'OCG01';
    end if;

    -- Reject offers that must be resumed or completed elsewhere
    if exists (
        select 1
        from admission_offer ao
        where ao.event_id = p_event_id
        and ao.user_id = p_user_id
        and admission_offer_reserves_seat(ao.status, ao.expires_at)
    ) then
        raise exception 'user already has an active admission offer for this event' using errcode = 'OCG01';
    end if;

    -- Allow reusing a live free hold only on direct simple RSVP events
    v_allows_free_hold_reuse := not v_event.attendee_approval_required
        and is_event_simple_rsvp(p_event_id);

    -- Reject purchases that already reserve enrollment
    if exists (
        select 1
        from event_purchase ep
        where ep.event_id = p_event_id
        and ep.user_id = p_user_id
        and (
            event_purchase_holds_seat(ep.status)
            or (
                ep.status = 'pending'
                and ep.hold_expires_at > current_timestamp
                and not v_allows_free_hold_reuse
            )
        )
    ) then
        raise exception 'user already has an active purchase for this event' using errcode = 'OCG01';
    end if;

    -- Resolve the selected or sole selectable public tier and its capacity
    select
        count(*)::int,
        (array_agg(
            ett.event_ticket_type_id
            order by ett."order", ett.event_ticket_type_id
        ))[1],
        (array_agg(
            ett.seats_total
            order by ett."order", ett.event_ticket_type_id
        ))[1]
    into
        v_selectable_public_ticket_count,
        v_resolved_ticket_type_id,
        v_ticket_seats_total
    from event_ticket_type ett
    where ett.event_id = p_event_id
    and (
        p_event_ticket_type_id is null
        or ett.event_ticket_type_id = p_event_ticket_type_id
    )
    and ett.active = true
    and ett.availability = 'public'
    and event_ticket_type_current_price(ett.event_ticket_type_id) is not null;

    -- Require one selectable public tier unless a generic private approval request is allowed
    if v_selectable_public_ticket_count <> 1
       and not (
            p_event_ticket_type_id is null
            and v_event.attendee_approval_required
            and v_selectable_public_ticket_count = 0
       ) then
        raise exception 'ticket type is required' using errcode = 'OCG01';
    end if;

    -- Continue with the resolved tier, or none for a generic private request
    p_event_ticket_type_id := v_resolved_ticket_type_id;

    -- Route approval-required enrollment into a public-tier or generic request
    if v_event.attendee_approval_required then
        -- Detect whether the request collects attendee details
        v_has_registration_questions :=
            jsonb_array_length(coalesce(v_event.registration_questions, '[]'::jsonb)) > 0;

        -- Validate answers when the request collects attendee details
        if v_has_registration_questions then
            perform validate_questionnaire_answers_payload(
                v_event.registration_questions,
                p_registration_answers
            );
        end if;

        -- Lock any earlier approval request by this attendee
        select eir.status
        into v_invitation_request_status
        from event_invitation_request eir
        where eir.event_id = p_event_id
        and eir.user_id = p_user_id
        for update of eir;

        -- Reject duplicate pending approval requests
        if v_invitation_request_status = 'pending' then
            raise exception 'user has already requested an invitation for this event' using errcode = 'OCG01';
        -- Reject previously denied approval requests
        elsif v_invitation_request_status = 'rejected' then
            raise exception 'invitation request was rejected for this event' using errcode = 'OCG01';
        -- Reject approval requests that already converted to an offer
        elsif v_invitation_request_status = 'accepted' then
            raise exception 'invitation request was already accepted for this event' using errcode = 'OCG01';
        end if;

        -- Record the pending approval request for the resolved tier
        insert into event_invitation_request (
            event_id,
            event_ticket_type_id,
            registration_answers,
            user_id
        ) values (
            p_event_id,
            p_event_ticket_type_id,
            p_registration_answers,
            p_user_id
        );

        -- Report the queued approval request
        return 'pending-approval';
    end if;

    -- Classify the live checkout holds against the resolved free tier
    select
        coalesce(bool_or(
            ep.event_ticket_type_id = p_event_ticket_type_id
            and ep.amount_minor = 0
        ), false),
        coalesce(bool_or(not (
            ep.event_ticket_type_id = p_event_ticket_type_id
            and ep.amount_minor = 0
        )), false)
    into
        v_has_reusable_free_purchase,
        v_has_blocking_purchase
    from event_purchase ep
    where ep.event_id = p_event_id
    and ep.user_id = p_user_id
    and ep.status = 'pending'
    and ep.hold_expires_at > current_timestamp;

    -- Reject purchase holds that cannot be safely reused
    if v_has_blocking_purchase then
        raise exception 'user already has an active purchase for this event' using errcode = 'OCG01';
    end if;

    -- Resume zero-value checkout when the existing hold is reusable
    if v_has_reusable_free_purchase then
        return 'pending-payment';
    end if;

    -- Return available seats to the handler-owned checkout fast path
    select get_event_ticket_type_allocated_seat_count(
        p_event_id,
        p_event_ticket_type_id
    )
    into v_ticket_allocated_count;

    -- Route into checkout when capacity remains
    if v_ticket_allocated_count < v_ticket_seats_total then
        return 'pending-payment';
    end if;

    -- Reject sold-out events with no waitlist
    if not v_event.waitlist_enabled then
        return 'event-capacity-unavailable';
    end if;

    -- Preserve FIFO priority for duplicate joins to the selected tier
    if exists (
        select 1
        from event_waitlist
        where event_id = p_event_id
        and event_ticket_type_id = p_event_ticket_type_id
        and user_id = p_user_id
    ) then
        return 'waitlisted';
    end if;

    -- Drop another queue position held by this attendee
    delete from event_waitlist
    where event_id = p_event_id
    and user_id = p_user_id;

    -- Drop inactive attendance replaced by the queue position
    delete from event_attendee
    where event_id = p_event_id
    and user_id = p_user_id
    and status in ('attendance-canceled', 'invitation-canceled');

    -- Queue the attendee for the selected tier
    insert into event_waitlist (
        event_id,
        event_ticket_type_id,
        user_id
    ) values (
        p_event_id,
        p_event_ticket_type_id,
        p_user_id
    );

    -- Report the new queue position
    return 'waitlisted';
end;
$$ language plpgsql;
