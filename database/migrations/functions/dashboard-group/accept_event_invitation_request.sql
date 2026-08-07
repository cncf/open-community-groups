-- Accepts an event invitation request and creates a tier-scoped admission offer.
create or replace function accept_event_invitation_request(
    p_actor_user_id uuid,
    p_group_id uuid,
    p_event_id uuid,
    p_user_id uuid,
    p_event_ticket_type_id uuid default null,
    p_configured_provider text default null
)
returns jsonb as $$
declare
    v_community_id uuid;
    v_ends_at timestamptz;
    v_event_name text;
    v_group_name text;
    v_is_simple_rsvp boolean;
    v_offer_expires_at timestamptz;
    v_offer_id uuid;
    v_payment_currency_code text;
    v_payment_recipient jsonb;
    v_promoted_user_ids uuid[];
    v_registration_ends_at timestamptz;
    v_registration_starts_at timestamptz;
    v_requested_ticket_type_id uuid;
    v_request_status text;
    v_starts_at timestamptz;
    v_target_price bigint;
    v_target_seats_total int;
    v_target_ticket_availability text;
    v_target_ticket_title text;
    v_theme jsonb;
    v_ticket_allocated_count int;
    v_timezone text;
begin
    -- Lock the event and load the enrollment context for organizer review
    select
        g.community_id,
        e.ends_at,
        e.name,
        g.name,
        e.payment_currency_code,
        g.payment_recipient,
        e.registration_ends_at,
        e.registration_starts_at,
        e.starts_at,
        e.timezone
    into
        v_community_id,
        v_ends_at,
        v_event_name,
        v_group_name,
        v_payment_currency_code,
        v_payment_recipient,
        v_registration_ends_at,
        v_registration_starts_at,
        v_starts_at,
        v_timezone
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

    -- Resolve attendee wording from the event's public ticket shape
    v_is_simple_rsvp := is_event_simple_rsvp(p_event_id);

    -- Lock ticket tiers before request-user and enrollment rows
    perform 1
    from event_ticket_type ett
    where ett.event_id = p_event_id
    order by ett.event_ticket_type_id
    for update of ett;

    -- Keep request review registration-bound until the event begins
    if not is_registration_window_open(
            v_registration_starts_at,
            v_registration_ends_at,
            v_starts_at
       )
       and (v_starts_at is null or v_starts_at > current_timestamp) then
        raise exception 'event registration is not open';
    end if;

    -- Resolve and lock the request tier before capacity allocation
    select
        eir.event_ticket_type_id,
        eir.status
    into
        v_requested_ticket_type_id,
        v_request_status
    from event_invitation_request eir
    where eir.event_id = p_event_id
    and eir.user_id = p_user_id
    and eir.status in ('accepted', 'pending')
    for update of eir;

    if not found then
        raise exception 'pending invitation request not found';
    end if;

    -- Preserve public requests or require an organizer-assigned private tier
    if v_requested_ticket_type_id is not null then
        if p_event_ticket_type_id is not null
           and p_event_ticket_type_id <> v_requested_ticket_type_id then
            raise exception 'requested ticket type cannot be changed';
        end if;

        p_event_ticket_type_id := v_requested_ticket_type_id;
    elsif p_event_ticket_type_id is null then
        raise exception 'invitation-only ticket type is required';
    end if;

    -- Load the requested public tier or organizer-assigned private tier
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
        v_target_price,
        v_target_ticket_availability,
        v_target_seats_total,
        v_target_ticket_title
    from event_ticket_type ett
    where ett.event_id = p_event_id
    and ett.event_ticket_type_id = p_event_ticket_type_id
    and ett.active = true
    and (
        v_requested_ticket_type_id is not null
        or ett.availability = 'invitation_only'
    );

    if not found or v_target_price is null then
        raise exception 'ticket type is not available';
    end if;

    -- Keep RSVP wording only for the event's free public tier
    v_is_simple_rsvp := v_is_simple_rsvp
        and v_target_ticket_availability = 'public'
        and v_target_price = 0;

    -- Reject request reissue while another enrollment state still blocks it
    if v_request_status = 'accepted'
       and exists (
            select 1
            from admission_offer ao
            where ao.event_id = p_event_id
            and ao.status in ('checkout_pending', 'pending')
            and ao.user_id = p_user_id
       ) then
        raise exception 'user already has an active admission offer for this event';
    end if;

    if v_request_status = 'accepted'
       and exists (
            select 1
            from event_purchase ep
            where ep.event_id = p_event_id
            and ep.status in (
                'completed',
                'pending',
                'refund-pending',
                'refund-recovery-pending',
                'refund-requested'
            )
            and ep.user_id = p_user_id
       ) then
        raise exception 'user already has an active purchase for this event';
    end if;

    -- Reconcile public queue priority and stale reservations before allocation
    v_promoted_user_ids := reconcile_event_enrollment(
        p_event_id,
        p_event_ticket_type_id,
        p_configured_provider
    );

    -- Serialize offer issuance with attendee and offer transitions
    perform pg_advisory_xact_lock(hashtext(p_event_id::text), hashtext(p_user_id::text));

    -- Re-lock the pending request after reconciliation settles queue state
    perform 1
    from event_invitation_request eir
    where eir.event_id = p_event_id
    and eir.user_id = p_user_id
    and eir.status = v_request_status
    for update of eir;

    if not found then
        raise exception 'pending invitation request not found';
    end if;

    -- Recheck tier capacity now that stale reservations are settled
    select get_event_ticket_type_allocated_seat_count(
        p_event_id,
        p_event_ticket_type_id
    )
    into v_ticket_allocated_count;

    -- Surface a conflict instead of overselling the target tier
    if v_target_seats_total is not null
       and v_ticket_allocated_count >= v_target_seats_total then
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
        v_target_price > 0,
        v_payment_currency_code,
        v_payment_recipient
    );

    -- Bound the offer lifetime by the applicable registration or event deadline
    if v_starts_at is not null and v_starts_at > current_timestamp then
        v_offer_expires_at := least(
            current_timestamp + interval '24 hours',
            coalesce(v_registration_ends_at, 'infinity'::timestamptz),
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

    -- Record the first organizer approval while preserving reviewed reissues
    if v_request_status = 'pending' then
        update event_invitation_request
        set
            reviewed_at = current_timestamp,
            reviewed_by = p_actor_user_id,
            status = 'accepted'
        where event_id = p_event_id
        and user_id = p_user_id
        and status = 'pending';
    end if;

    -- Reserve the seat with a pending admission offer
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
        'approval',
        'pending',
        p_user_id
    )
    returning admission_offer_id into v_offer_id;

    -- Notify the requester only after the offer reservation exists
    select s.theme
    into v_theme
    from site s
    limit 1;

    perform enqueue_notification(
        'event-ticket-request-approved',
        jsonb_build_object(
            'admission_offer_id', v_offer_id,
            'amount_minor', v_target_price,
            'currency_code', v_payment_currency_code,
            'dashboard_url', format(
                '/dashboard/user?tab=invitations#event-offer-%s',
                v_offer_id
            ),
            'event_id', p_event_id,
            'event_name', v_event_name,
            'event_ticket_type_id', p_event_ticket_type_id,
            'expires_at', extract(epoch from v_offer_expires_at)::bigint,
            'group_name', v_group_name,
            'is_simple_rsvp', v_is_simple_rsvp,
            'theme', v_theme,
            'ticket_title', v_target_ticket_title,
            'timezone', v_timezone,
            'user_id', p_user_id
        ),
        '[]'::jsonb,
        array[p_user_id]
    );

    -- Track the organizer decision after its enrollment transition succeeds
    perform insert_audit_log(
        case
            when v_request_status = 'accepted' then 'event_admission_offer_reissued'
            else 'event_invitation_request_accepted'
        end,
        p_actor_user_id,
        'user',
        p_user_id,
        v_community_id,
        p_group_id,
        p_event_id,
        jsonb_strip_nulls(jsonb_build_object(
            'admission_offer_id', v_offer_id,
            'event_id', p_event_id,
            'event_ticket_type_id', p_event_ticket_type_id,
            'user_id', p_user_id
        ))
    );

    -- Return the acceptance outcome
    return jsonb_strip_nulls(jsonb_build_object(
        'admission_offer_id', v_offer_id,
        'outcome', 'offer-created',
        'user_id', p_user_id
    ));
end;
$$ language plpgsql;
