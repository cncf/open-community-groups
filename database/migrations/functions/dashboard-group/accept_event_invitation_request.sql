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
    v_capacity_conflict text;
    v_event event;
    v_group "group";
    v_is_simple_rsvp boolean;
    v_offer_expires_at timestamptz;
    v_offer_id uuid;
    v_promoted_user_ids uuid[];
    v_request event_invitation_request;
    v_target_price bigint;
    v_theme jsonb;
    v_ticket_type event_ticket_type;
begin
    -- Lock the event and load the enrollment context for organizer review
    v_event := lock_active_event(null, p_group_id, p_event_id, true);

    -- Reject review when the event is not an active approval event
    if v_event.attendee_approval_required is distinct from true then
        raise exception 'event not found or inactive' using errcode = 'OCG01';
    end if;

    -- Load group context needed for notifications and audit
    select g.*
    into v_group
    from "group" g
    where g.group_id = v_event.group_id;

    -- Resolve attendee wording from the event's public ticket shape
    v_is_simple_rsvp := is_event_simple_rsvp(p_event_id);

    -- Lock ticket tiers before request-user and enrollment rows
    perform 1
    from event_ticket_type ett
    where ett.event_id = p_event_id
    order by ett.event_ticket_type_id
    for update of ett;

    -- Resolve and lock the request tier before capacity allocation
    select eir.*
    into v_request
    from event_invitation_request eir
    where eir.event_id = p_event_id
    and eir.user_id = p_user_id
    and eir.status in ('accepted', 'pending')
    for update of eir;

    -- Reject review when no pending or reissueable request exists
    if not found then
        raise exception 'pending invitation request not found' using errcode = 'OCG01';
    end if;

    -- Preserve public requests or require an organizer-assigned private tier
    if v_request.event_ticket_type_id is not null then
        -- Reject organizer overrides of a requester-selected public tier
        if p_event_ticket_type_id is not null
           and p_event_ticket_type_id <> v_request.event_ticket_type_id then
            raise exception 'requested ticket type cannot be changed' using errcode = 'OCG01';
        end if;

        p_event_ticket_type_id := v_request.event_ticket_type_id;

    -- Require a private-tier assignment for generic invitation-only requests
    elsif p_event_ticket_type_id is null then
        raise exception 'invitation-only ticket type is required' using errcode = 'OCG01';
    end if;

    -- Load the requested public tier or organizer-assigned private tier
    select ett.*
    into v_ticket_type
    from event_ticket_type ett
    where ett.event_id = p_event_id
    and ett.event_ticket_type_id = p_event_ticket_type_id
    and ett.active = true
    and (
        v_request.event_ticket_type_id is not null
        or ett.availability = 'invitation_only'
    );

    -- Reject inactive or ineligible ticket assignments
    if not found then
        raise exception 'ticket type is not available' using errcode = 'OCG01';
    end if;

    -- Reject tiers without a current price
    v_target_price := event_ticket_type_current_price(v_ticket_type.event_ticket_type_id);
    if v_target_price is null then
        raise exception 'ticket type is not available' using errcode = 'OCG01';
    end if;

    -- Keep RSVP wording only for the event's free public tier
    v_is_simple_rsvp := v_is_simple_rsvp
        and v_ticket_type.availability = 'public'
        and v_target_price = 0;

    -- Reject request reissue while another enrollment state still blocks it
    if v_request.status = 'accepted'
       and exists (
            select 1
            from admission_offer ao
            where ao.event_id = p_event_id
            and admission_offer_is_active(ao.status)
            and ao.user_id = p_user_id
       ) then
        raise exception 'user already has an active admission offer for this event' using errcode = 'OCG01';
    end if;

    -- Reject request reissue while an active purchase still occupies the seat
    if v_request.status = 'accepted'
       and exists (
            select 1
            from event_purchase ep
            where ep.event_id = p_event_id
            and (
                event_purchase_holds_seat(ep.status)
                or ep.status = 'pending'
            )
            and ep.user_id = p_user_id
       ) then
        raise exception 'user already has an active purchase for this event' using errcode = 'OCG01';
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
    and eir.status = v_request.status
    for update of eir;

    -- Reject review when reconciliation removed the request
    if not found then
        raise exception 'pending invitation request not found' using errcode = 'OCG01';
    end if;

    -- Surface a conflict instead of overselling the target tier now that stale reservations are settled
    v_capacity_conflict := admission_offer_capacity_conflict(v_ticket_type, v_promoted_user_ids);
    if v_capacity_conflict is not null then
        return jsonb_build_object('conflict', v_capacity_conflict);
    end if;

    -- Ensure payments can be collected before reserving a paid seat
    perform validate_admission_offer_payment_readiness(
        v_event,
        v_group,
        v_target_price,
        p_configured_provider
    );

    -- Bound the invitation expiry to the remaining event window
    v_offer_expires_at := resolve_organizer_offer_expiry(v_event);

    -- Record the first organizer approval while preserving reviewed reissues
    if v_request.status = 'pending' then
        update event_invitation_request
        set
            reviewed_at = current_timestamp,
            reviewed_by = p_actor_user_id,
            status = 'accepted'
        where event_id = p_event_id
        and user_id = p_user_id
        and status = 'pending';
    end if;

    -- Reserve the seat with a pending admission offer and its issue price
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
        v_target_price,
        case
            -- Keep intrinsic-free snapshots currency-free
            when v_target_price > 0 then v_event.payment_currency_code
            -- Drop event currency from free approval offers
            else null
        end,
        0,
        p_event_id,
        p_event_ticket_type_id,
        v_offer_expires_at,
        p_actor_user_id,
        'approval',
        'pending',
        v_ticket_type.title,
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
            'currency_code', v_event.payment_currency_code,
            'dashboard_url', format(
                '/dashboard/user?tab=invitations#event-offer-%s',
                v_offer_id
            ),
            'event_id', p_event_id,
            'event_name', v_event.name,
            'event_ticket_type_id', p_event_ticket_type_id,
            'expires_at', epoch_seconds(v_offer_expires_at),
            'group_name', v_group.name,
            'is_simple_rsvp', v_is_simple_rsvp,
            'theme', v_theme,
            'ticket_title', v_ticket_type.title,
            'timezone', v_event.timezone,
            'user_id', p_user_id
        ),
        '[]'::jsonb,
        array[p_user_id]
    );

    -- Track the organizer decision after its enrollment transition succeeds
    perform insert_audit_log(
        case
            -- Reissues keep the original approval and record a new offer
            when v_request.status = 'accepted' then 'event_admission_offer_reissued'
            -- First reviews record the organizer acceptance
            else 'event_invitation_request_accepted'
        end,
        p_actor_user_id,
        'user',
        p_user_id,
        v_group.community_id,
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
