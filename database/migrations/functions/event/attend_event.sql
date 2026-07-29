-- Routes an attendee into checkout, approval, or a tier-scoped waitlist.
create or replace function attend_event(
    p_community_id uuid,
    p_event_id uuid,
    p_user_id uuid,
    p_registration_answers jsonb default null,
    p_event_ticket_type_id uuid default null
) returns text as $$
declare
    v_attendee_approval_required boolean;
    v_has_reusable_free_purchase boolean;
    v_has_registration_questions boolean;
    v_invitation_request_status text;
    v_registration_ends_at timestamptz;
    v_registration_questions jsonb;
    v_registration_starts_at timestamptz;
    v_selectable_public_ticket_count int;
    v_starts_at timestamptz;
    v_ticket_allocated_count int;
    v_ticket_seats_total int;
    v_waitlist_enabled boolean;
begin
    -- Lock and validate the attendee-visible event
    select
        e.attendee_approval_required,
        e.registration_ends_at,
        e.registration_questions,
        e.registration_starts_at,
        e.starts_at,
        e.waitlist_enabled
    into
        v_attendee_approval_required,
        v_registration_ends_at,
        v_registration_questions,
        v_registration_starts_at,
        v_starts_at,
        v_waitlist_enabled
    from event e
    join "group" g using (group_id)
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
        v_registration_starts_at,
        v_registration_ends_at,
        v_starts_at
    ) then
        raise exception 'event registration is not open';
    end if;

    -- Reject enrollment state that must be resumed or completed elsewhere
    if exists (
        select 1
        from event_attendee ea
        where ea.event_id = p_event_id
        and ea.user_id = p_user_id
        and ea.status = 'confirmed'
    ) then
        raise exception 'user is already attending this event';
    end if;

    if exists (
        select 1
        from admission_offer ao
        where ao.event_id = p_event_id
        and ao.user_id = p_user_id
        and ao.status in ('checkout_pending', 'pending')
        and ao.expires_at > current_timestamp
    ) then
        raise exception 'user already has an active admission offer for this event';
    end if;

    if exists (
        select 1
        from event_purchase ep
        where ep.event_id = p_event_id
        and ep.user_id = p_user_id
        and (
            ep.status in (
                'completed',
                'refund-pending',
                'refund-recovery-pending',
                'refund-requested'
            )
            or (
                ep.status = 'pending'
                and ep.hold_expires_at > current_timestamp
                and (
                    v_attendee_approval_required
                    or not is_event_simple_rsvp(p_event_id)
                )
            )
        )
    ) then
        raise exception 'user already has an active purchase for this event';
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
        and exists (
            select 1
            from event_ticket_price_window etpw
            where etpw.event_ticket_type_id = ett.event_ticket_type_id
            and (etpw.starts_at is null or etpw.starts_at <= current_timestamp)
            and (etpw.ends_at is null or etpw.ends_at >= current_timestamp)
        );

        if v_selectable_public_ticket_count <> 1
           and not (
                v_attendee_approval_required
                and v_selectable_public_ticket_count = 0
           ) then
            raise exception 'ticket type is required';
        end if;
    else
        select count(*)::int
        into v_selectable_public_ticket_count
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

        if v_selectable_public_ticket_count <> 1 then
            raise exception 'ticket type is required';
        end if;
    end if;

    -- Route approval-required enrollment into a public-tier or generic request
    if v_attendee_approval_required then
        v_has_registration_questions :=
            jsonb_array_length(coalesce(v_registration_questions, '[]'::jsonb)) > 0;

        if v_has_registration_questions then
            perform validate_questionnaire_answers_payload(
                v_registration_questions,
                p_registration_answers
            );
        end if;

        select eir.status
        into v_invitation_request_status
        from event_invitation_request eir
        where eir.event_id = p_event_id
        and eir.user_id = p_user_id
        for update of eir;

        if v_invitation_request_status = 'pending' then
            raise exception 'user has already requested an invitation for this event';
        elsif v_invitation_request_status = 'rejected' then
            raise exception 'invitation request was rejected for this event';
        elsif v_invitation_request_status = 'accepted' then
            raise exception 'invitation request was already accepted for this event';
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

    if not found then
        raise exception 'ticket type is not publicly available';
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
        and not v_attendee_approval_required
    )
    into v_has_reusable_free_purchase;

    if exists (
        select 1
        from event_purchase ep
        where ep.event_id = p_event_id
        and ep.user_id = p_user_id
        and (
            ep.status in (
                'completed',
                'refund-pending',
                'refund-recovery-pending',
                'refund-requested'
            )
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
        raise exception 'user already has an active purchase for this event';
    end if;

    if v_has_reusable_free_purchase then
        return 'pending-payment';
    end if;

    -- Return available seats to the handler-owned checkout fast path
    select get_event_ticket_type_allocated_seat_count(
        p_event_id,
        p_event_ticket_type_id
    )
    into v_ticket_allocated_count;

    if v_ticket_allocated_count < v_ticket_seats_total then
        return 'pending-payment';
    end if;

    if not v_waitlist_enabled then
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
