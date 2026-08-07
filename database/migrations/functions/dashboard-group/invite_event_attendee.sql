-- Creates an organizer event invitation for a registered or pre-registered user.
create or replace function invite_event_attendee(
    p_actor_user_id uuid,
    p_group_id uuid,
    p_event_id uuid,
    p_user_id uuid,
    p_email text,
    p_event_ticket_type_id uuid default null,
    p_configured_provider text default null
)
returns jsonb as $$
declare
    v_admission_offer_id uuid;
    v_community_id uuid;
    v_create_pre_registered_user boolean := false;
    v_ends_at timestamptz;
    v_event_name text;
    v_existing_status text;
    v_existing_user_email_verified boolean;
    v_existing_user_registration_status text;
    v_group_name text;
    v_has_registration_questions boolean;
    v_is_simple_rsvp boolean;
    v_normalized_email text := lower(nullif(btrim(p_email), ''));
    v_offer_expires_at timestamptz;
    v_payment_currency_code text;
    v_payment_recipient jsonb;
    v_promoted_user_ids uuid[];
    v_registration_questions jsonb;
    v_selectable_ticket_type_count int;
    v_starts_at timestamptz;
    v_target_user_id uuid;
    v_theme jsonb;
    v_ticket_allocated_count int;
    v_ticket_availability text;
    v_ticket_current_price bigint;
    v_ticket_seats_total int;
    v_ticket_title text;
    v_timezone text;
begin
    -- Validate invitation target shape
    if (p_user_id is null and v_normalized_email is null)
       or (p_user_id is not null and v_normalized_email is not null) then
        raise exception 'provide exactly one invite target';
    end if;

    -- Lock and validate the event before ticket and attendee enrollment state
    select
        g.community_id,
        e.ends_at,
        e.name,
        g.name,
        e.payment_currency_code,
        g.payment_recipient,
        e.registration_questions,
        e.starts_at,
        e.timezone
    into
        v_community_id,
        v_ends_at,
        v_event_name,
        v_group_name,
        v_payment_currency_code,
        v_payment_recipient,
        v_registration_questions,
        v_starts_at,
        v_timezone
    from event e
    join "group" g using (group_id)
    where e.event_id = p_event_id
    and e.group_id = p_group_id
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

    -- Lock ticket tiers before reconciliation and target-user enrollment state
    perform 1
    from event_ticket_type ett
    where ett.event_id = p_event_id
    order by ett.event_ticket_type_id
    for update of ett;

    v_has_registration_questions :=
        jsonb_array_length(coalesce(v_registration_questions, '[]'::jsonb)) > 0;
    v_is_simple_rsvp := is_event_simple_rsvp(p_event_id);

    -- Resolve registered or pre-register email invitee
    if p_user_id is not null then
        select u.user_id
        into v_target_user_id
        from "user" u
        where u.user_id = p_user_id
        and u.registration_status = 'registered'
        and u.email_verified = true;

        if not found then
            raise exception 'registered user not found';
        end if;
    else
        -- Serialize pre-registration by normalized email across different events
        perform pg_advisory_xact_lock(
            hashtext('invite-event-attendee-email'),
            hashtext(v_normalized_email)
        );

        -- Recheck the user catalog after acquiring the email lock
        select
            u.email_verified,
            u.registration_status,
            u.user_id
        into
            v_existing_user_email_verified,
            v_existing_user_registration_status,
            v_target_user_id
        from "user" u
        where lower(u.email) = v_normalized_email;

        if not found then
            v_create_pre_registered_user := true;
            v_target_user_id := gen_random_uuid();
        elsif v_existing_user_registration_status = 'registered'
              and v_existing_user_email_verified = false then
            raise exception 'registered user email is not verified';
        end if;
    end if;

    -- Auto-select the sole organizer-visible tier when the form omits it
    if p_event_ticket_type_id is null then
        select
            count(*)::int,
            (array_agg(
                ett.event_ticket_type_id
                order by ett."order", ett.event_ticket_type_id
            ))[1]
        into
            v_selectable_ticket_type_count,
            p_event_ticket_type_id
        from event_ticket_type ett
        where ett.event_id = p_event_id
        and ett.active = true
        and exists (
            select 1
            from event_ticket_price_window etpw
            where etpw.event_ticket_type_id = ett.event_ticket_type_id
            and (etpw.starts_at is null or etpw.starts_at <= current_timestamp)
            and (etpw.ends_at is null or etpw.ends_at >= current_timestamp)
        );

        if v_selectable_ticket_type_count <> 1 then
            raise exception 'ticket type is required for event invitations';
        end if;
    end if;

    -- Resolve the organizer-selected ticket tier and current base price
    select
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
        ett.availability,
        ett.seats_total,
        ett.title
    into
        v_ticket_current_price,
        v_ticket_availability,
        v_ticket_seats_total,
        v_ticket_title
    from event_ticket_type ett
    where ett.event_id = p_event_id
    and ett.event_ticket_type_id = p_event_ticket_type_id
    and ett.active = true;

    if not found or v_ticket_current_price is null then
        raise exception 'ticket type is not available';
    end if;

    -- Keep RSVP wording only for the event's free public tier
    v_is_simple_rsvp := v_is_simple_rsvp
        and v_ticket_availability = 'public'
        and v_ticket_current_price = 0;

    -- Reconcile stale reservations and public queue priority before allocation
    v_promoted_user_ids := reconcile_event_enrollment(
        p_event_id,
        p_event_ticket_type_id,
        p_configured_provider
    );

    -- Reuse the queue promotion when reconciliation already seated the target
    if v_target_user_id = any(coalesce(v_promoted_user_ids, array[]::uuid[])) then
        select ao.admission_offer_id
        into v_admission_offer_id
        from admission_offer ao
        where ao.event_id = p_event_id
        and ao.event_ticket_type_id = p_event_ticket_type_id
        and ao.source = 'waitlist'
        and ao.status = 'pending'
        and ao.user_id = v_target_user_id;

        return jsonb_build_object(
            'admission_offer_id', v_admission_offer_id,
            'outcome', 'queue-offer',
            'user_id', v_target_user_id
        );
    end if;

    -- Serialize offer issuance with attendee and offer transitions
    perform pg_advisory_xact_lock(
        hashtext(p_event_id::text),
        hashtext(v_target_user_id::text)
    );

    -- Recheck tier capacity now that stale reservations are settled
    select get_event_ticket_type_allocated_seat_count(
        p_event_id,
        p_event_ticket_type_id
    )
    into v_ticket_allocated_count;

    -- Surface a conflict instead of overselling the target tier
    if v_ticket_seats_total is not null
       and v_ticket_allocated_count >= v_ticket_seats_total then
        return jsonb_build_object(
            'conflict',
            case
                when cardinality(v_promoted_user_ids) > 0
                    then 'queue-has-priority'
                else 'ticket-type-sold-out'
            end
        );
    end if;

    -- Ensure payments can be collected before reserving a paid seat
    perform validate_event_ticketing_payment_readiness(
        p_configured_provider,
        v_ticket_current_price > 0,
        v_payment_currency_code,
        v_payment_recipient
    );

    -- Reject attendee and offer states that should not be invited again
    select ea.status
    into v_existing_status
    from event_attendee ea
    where ea.event_id = p_event_id
    and ea.user_id = v_target_user_id
    for update of ea;

    if v_existing_status = 'confirmed' then
        raise exception 'user is already attending this event';
    end if;

    if v_existing_status = 'invitation-pending' then
        raise exception 'user already has a pending event invitation';
    end if;

    if v_existing_status = 'registration-questions-pending' then
        raise exception 'user already has a pending event registration';
    end if;

    if exists (
        select 1
        from admission_offer ao
        where ao.event_id = p_event_id
        and ao.status in ('checkout_pending', 'pending')
        and ao.user_id = v_target_user_id
    ) then
        raise exception 'user already has a pending event invitation';
    end if;

    -- Persist a new email invitee only after capacity allocation succeeds
    if v_create_pre_registered_user then
        insert into "user" (
            auth_hash,
            email,
            email_verified,
            registration_status,
            user_id,
            username
        ) values (
            encode(gen_random_bytes(32), 'hex'),
            v_normalized_email,
            false,
            'pre-registered',
            v_target_user_id,
            'invited-' || substr(
                encode(digest(convert_to(v_normalized_email, 'utf8'), 'sha256'), 'hex'),
                1,
                24
            )
        );
    end if;

    -- Move a public waitlist user atomically into the organizer-selected offer
    delete from event_waitlist
    where event_id = p_event_id
    and user_id = v_target_user_id;

    -- Bound the invitation expiry to the remaining event window
    if v_starts_at is not null and v_starts_at > current_timestamp then
        v_offer_expires_at := least(
            current_timestamp + interval '24 hours',
            v_starts_at
        );
    else
        v_offer_expires_at := least(
            current_timestamp + interval '24 hours',
            coalesce(v_ends_at, 'infinity'::timestamptz)
        );
    end if;

    if v_offer_expires_at <= current_timestamp then
        raise exception 'event not found or inactive';
    end if;

    -- Create the time-limited organizer invitation reservation
    insert into admission_offer (
        event_id,
        event_ticket_type_id,
        expires_at,
        organizer_user_id,
        source,
        status,
        user_id
    ) values (
        p_event_id,
        p_event_ticket_type_id,
        v_offer_expires_at,
        p_actor_user_id,
        'organizer_invitation',
        'pending',
        v_target_user_id
    )
    returning admission_offer_id into v_admission_offer_id;

    -- Enqueue the invitation notification in the offer transaction
    select s.theme
    into v_theme
    from site s
    limit 1;

    perform enqueue_notification(
        'event-admission-offer-created',
        jsonb_strip_nulls(jsonb_build_object(
            'admission_offer_id', v_admission_offer_id,
            'amount_minor', v_ticket_current_price,
            'currency_code', v_payment_currency_code,
            'dashboard_url', format(
                '/dashboard/user?tab=invitations#event-offer-%s',
                v_admission_offer_id
            ),
            'event_id', p_event_id,
            'event_name', v_event_name,
            'event_ticket_type_id', p_event_ticket_type_id,
            'expires_at', extract(epoch from v_offer_expires_at)::bigint,
            'group_name', v_group_name,
            'is_simple_rsvp', v_is_simple_rsvp,
            'registration_questions_required', v_has_registration_questions,
            'theme', v_theme,
            'ticket_title', v_ticket_title,
            'timezone', v_timezone,
            'user_id', v_target_user_id
        )),
        '[]'::jsonb,
        array[v_target_user_id]
    );

    -- Track the invitation after its reservation and notification exist
    perform insert_audit_log(
        'event_attendee_invitation_sent',
        p_actor_user_id,
        'user',
        v_target_user_id,
        v_community_id,
        p_group_id,
        p_event_id,
        jsonb_strip_nulls(jsonb_build_object(
            'admission_offer_id', v_admission_offer_id,
            'event_id', p_event_id,
            'event_ticket_type_id', p_event_ticket_type_id,
            'registration_questions_required', v_has_registration_questions,
            'user_id', v_target_user_id
        ))
    );

    -- Return the invitation outcome
    return jsonb_build_object(
        'admission_offer_id', v_admission_offer_id,
        'outcome', 'offer-created',
        'user_id', v_target_user_id
    );
end;
$$ language plpgsql;
