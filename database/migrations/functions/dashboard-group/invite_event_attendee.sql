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
    v_capacity_conflict text;
    v_create_pre_registered_user boolean := false;
    v_event event;
    v_existing_status text;
    v_group "group";
    v_has_registration_questions boolean;
    v_is_simple_rsvp boolean;
    v_normalized_email text := lower(nullif(btrim(p_email), ''));
    v_offer_expires_at timestamptz;
    v_promoted_user_ids uuid[];
    v_selectable_ticket_type_count int;
    v_target_user "user";
    v_target_user_id uuid;
    v_theme jsonb;
    v_ticket_current_price bigint;
    v_ticket_type event_ticket_type;
begin
    -- Validate invitation target shape
    if (p_user_id is null and v_normalized_email is null)
       or (p_user_id is not null and v_normalized_email is not null) then
        raise exception 'provide exactly one invite target' using errcode = 'OCG01';
    end if;

    -- Lock and validate the event before ticket and attendee enrollment state
    v_event := lock_active_event(null, p_group_id, p_event_id, true);

    -- Load group context needed for payment validation, notifications and audit
    select g.*
    into v_group
    from "group" g
    where g.group_id = v_event.group_id;

    -- Lock ticket tiers before reconciliation and target-user enrollment state
    perform 1
    from event_ticket_type ett
    where ett.event_id = p_event_id
    order by ett.event_ticket_type_id
    for update of ett;

    v_has_registration_questions :=
        jsonb_array_length(coalesce(v_event.registration_questions, '[]'::jsonb)) > 0;
    v_is_simple_rsvp := is_event_simple_rsvp(p_event_id);

    -- Resolve a registered invitee by identifier
    if p_user_id is not null then
        select u.*
        into v_target_user
        from "user" u
        where u.user_id = p_user_id
        and u.registration_status = 'registered'
        and u.email_verified = true;

        -- Reject unknown or unverified registered invitees
        if not found then
            raise exception 'registered user not found' using errcode = 'OCG01';
        end if;

        v_target_user_id := v_target_user.user_id;

    -- Resolve or pre-register the email invitee
    else
        -- Serialize pre-registration by normalized email across different events
        perform pg_advisory_xact_lock(
            hashtext('invite-event-attendee-email'),
            hashtext(v_normalized_email)
        );

        -- Recheck the user catalog after acquiring the email lock
        select u.*
        into v_target_user
        from "user" u
        where lower(u.email) = v_normalized_email;

        -- Create a pre-registered user for a new invitee email
        if not found then
            v_create_pre_registered_user := true;
            v_target_user_id := gen_random_uuid();

        -- Reject registered accounts whose email is still unverified
        elsif v_target_user.registration_status = 'registered'
              and v_target_user.email_verified = false then
            raise exception 'registered user email is not verified' using errcode = 'OCG01';

        -- Invite the existing account behind the email
        else
            v_target_user_id := v_target_user.user_id;
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
        and event_ticket_type_current_price(ett.event_ticket_type_id) is not null;

        -- Require an explicit tier when more than one organizer-visible tier exists
        if v_selectable_ticket_type_count <> 1 then
            raise exception 'ticket type is required for event invitations' using errcode = 'OCG01';
        end if;
    end if;

    -- Resolve the organizer-selected ticket tier and current base price
    select ett.*
    into v_ticket_type
    from event_ticket_type ett
    where ett.event_id = p_event_id
    and ett.event_ticket_type_id = p_event_ticket_type_id
    and ett.active = true;

    -- Reject missing or inactive invitation tiers
    if not found then
        raise exception 'ticket type is not available' using errcode = 'OCG01';
    end if;

    -- Reject tiers without a current price
    v_ticket_current_price := event_ticket_type_current_price(v_ticket_type.event_ticket_type_id);
    if v_ticket_current_price is null then
        raise exception 'ticket type is not available' using errcode = 'OCG01';
    end if;

    -- Keep RSVP wording only for the event's free public tier
    v_is_simple_rsvp := v_is_simple_rsvp
        and v_ticket_type.availability = 'public'
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

    -- Surface a conflict instead of overselling the target tier now that stale reservations are settled
    v_capacity_conflict := admission_offer_capacity_conflict(v_ticket_type, v_promoted_user_ids);
    if v_capacity_conflict is not null then
        return jsonb_build_object('conflict', v_capacity_conflict);
    end if;

    -- Ensure payments can be collected before reserving a paid seat
    perform validate_admission_offer_payment_readiness(
        v_event,
        v_group,
        v_ticket_current_price,
        p_configured_provider
    );

    -- Lock the attendee row whose state decides whether the user can be invited again
    select ea.status
    into v_existing_status
    from event_attendee ea
    where ea.event_id = p_event_id
    and ea.user_id = v_target_user_id
    for update of ea;

    -- Reject confirmed attendees who already hold a seat
    if v_existing_status = 'confirmed' then
        raise exception 'user is already attending this event' using errcode = 'OCG01';
    end if;

    -- Reject invitees who already have a pending attendance invitation
    if v_existing_status = 'invitation-pending' then
        raise exception 'user already has a pending event invitation' using errcode = 'OCG01';
    end if;

    -- Reject invitees who still owe registration answers
    if v_existing_status = 'registration-questions-pending' then
        raise exception 'user already has a pending event registration' using errcode = 'OCG01';
    end if;

    -- Reject invitees who already have an active offer reservation
    if exists (
        select 1
        from admission_offer ao
        where ao.event_id = p_event_id
        and admission_offer_is_active(ao.status)
        and ao.user_id = v_target_user_id
    ) then
        raise exception 'user already has a pending event invitation' using errcode = 'OCG01';
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
    v_offer_expires_at := resolve_organizer_offer_expiry(v_event);

    -- Create the time-limited organizer invitation reservation
    insert into admission_offer (
        amount_minor,
        currency_code,
        discount_amount_minor,
        event_id,
        event_ticket_type_id,
        expires_at,
        organizer_user_id,
        source,
        status,
        ticket_title,
        user_id
    ) values (
        v_ticket_current_price,
        case
            -- Keep intrinsic-free snapshots currency-free
            when v_ticket_current_price > 0 then v_event.payment_currency_code
            -- Drop event currency from free organizer invitations
            else null
        end,
        0,
        p_event_id,
        p_event_ticket_type_id,
        v_offer_expires_at,
        p_actor_user_id,
        'organizer_invitation',
        'pending',
        v_ticket_type.title,
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
            'currency_code', v_event.payment_currency_code,
            'dashboard_url', format(
                '/dashboard/user?tab=invitations#event-offer-%s',
                v_admission_offer_id
            ),
            'event_id', p_event_id,
            'event_name', v_event.name,
            'event_ticket_type_id', p_event_ticket_type_id,
            'expires_at', epoch_seconds(v_offer_expires_at),
            'group_name', v_group.name,
            'is_simple_rsvp', v_is_simple_rsvp,
            'registration_questions_required', v_has_registration_questions,
            'theme', v_theme,
            'ticket_title', v_ticket_type.title,
            'timezone', v_event.timezone,
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
        v_group.community_id,
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
