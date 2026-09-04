-- Routes an attendee into checkout, approval, or a tier-scoped waitlist.
create or replace function attend_event(
    p_community_id uuid,
    p_event_id uuid,
    p_user_id uuid,
    p_registration_answers jsonb default null,
    p_event_ticket_type_id uuid default null
) returns text as $$
declare
    v_event event;
    v_has_reusable_free_purchase boolean;
    v_has_registration_questions boolean;
    v_invitation_request_status text;
    v_selectable_public_ticket_count int;
    v_ticket_allocated_count int;
    v_ticket_seats_total int;
begin
    -- Lock and validate the attendee-visible event
    v_event := lock_active_event(p_community_id, null, p_event_id, true);

    -- Lock tiers and reconcile stale reservations before serializing this attendee
    perform 1
    from event_ticket_type ett
    where ett.event_id = p_event_id
    order by ett.event_ticket_type_id
    for update of ett;

    perform reconcile_event_enrollment(
        p_event_id,
        null,
        null
    );

    perform pg_advisory_xact_lock(hashtext(p_event_id::text), hashtext(p_user_id::text));

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
        and admission_offer_is_active(ao.status)
        and ao.expires_at > current_timestamp
    ) then
        raise exception 'user already has an active admission offer for this event' using errcode = 'OCG01';
    end if;

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
                and (v_event.attendee_approval_required or not is_event_simple_rsvp(p_event_id))
            )
        )
    ) then
        raise exception 'user already has an active purchase for this event' using errcode = 'OCG01';
    end if;

    -- Resolve a selected public tier or preserve a fully private generic request
    if p_event_ticket_type_id is null then
        select
            count(*)::int,
            (array_agg(
                ett.event_ticket_type_id
                order by ett."order", ett.event_ticket_type_id
            ))[1]
        into
            v_selectable_public_ticket_count,
            p_event_ticket_type_id
        from event_ticket_type ett
        where ett.event_id = p_event_id
        and ett.active = true
        and ett.availability = 'public'
        and event_ticket_type_current_price(ett.event_ticket_type_id) is not null;

        -- Require one public tier unless private approval requests are allowed
        if v_selectable_public_ticket_count <> 1
           and not (
                v_event.attendee_approval_required
                and v_selectable_public_ticket_count = 0
           ) then
            raise exception 'ticket type is required' using errcode = 'OCG01';
        end if;
    else
        select count(*)::int
        into v_selectable_public_ticket_count
        from event_ticket_type ett
        where ett.event_id = p_event_id
        and ett.event_ticket_type_id = p_event_ticket_type_id
        and ett.active = true
        and ett.availability = 'public'
        and event_ticket_type_current_price(ett.event_ticket_type_id) is not null;

        -- Require the selected tier to be public and purchasable
        if v_selectable_public_ticket_count <> 1 then
            raise exception 'ticket type is required' using errcode = 'OCG01';
        end if;
    end if;

    -- Route approval-required enrollment into a public-tier or generic request
    if v_event.attendee_approval_required then
        v_has_registration_questions :=
            jsonb_array_length(coalesce(v_event.registration_questions, '[]'::jsonb)) > 0;

        -- Validate answers when the request collects attendee details
        if v_has_registration_questions then
            perform validate_questionnaire_answers_payload(
                v_event.registration_questions,
                p_registration_answers
            );
        end if;

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

        return 'pending-approval';
    end if;

    -- Load the selected tier capacity after validating public availability
    select ett.seats_total
    into v_ticket_seats_total
    from event_ticket_type ett
    where ett.event_id = p_event_id
    and ett.event_ticket_type_id = p_event_ticket_type_id
    and ett.active = true
    and ett.availability = 'public';

    -- Reject unavailable tiers that should not reach checkout
    if not found then
        raise exception 'ticket type is not publicly available' using errcode = 'OCG01';
    end if;

    -- Reuse interrupted zero-value checkout holds for the selected tier
    select exists (
        select 1
        from event_purchase ep
        where ep.event_id = p_event_id
        and ep.event_ticket_type_id = p_event_ticket_type_id
        and ep.user_id = p_user_id
        and ep.amount_minor = 0
        and ep.status = 'pending'
        and ep.hold_expires_at > current_timestamp
        and not v_event.attendee_approval_required
    )
    into v_has_reusable_free_purchase;

    -- Reject purchase holds that cannot be safely reused
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
                and not (
                    ep.event_ticket_type_id = p_event_ticket_type_id
                    and ep.amount_minor = 0
                )
            )
        )
    ) then
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

    -- Replace inactive attendance or another queue position with this tier queue
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
end;
$$ language plpgsql;
