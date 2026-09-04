-- Resolves the enrollment state of a user for an event from every table that
-- records it. Returns the raw facts (attendee row, active admission offer,
-- relevant purchase, refund request, invitation request, waitlist) together
-- with one derived state so callers agree on the precedence between them.
--
-- Derived states, strongest first: confirmed (seat held), payment-pending
-- (unexpired pending purchase), offer-active (unexpired admission offer not
-- being refunded), registration-pending, invitation-pending,
-- invitation-declined (attendee rows waiting on the user), approval-pending,
-- approval-rejected (invitation requests), waitlisted, offer-expired (latest
-- offer lapsed) and none. Callers map these to their own labels and apply
-- their own locks before mutating.
create or replace function event_user_enrollment(
    p_event_id uuid,
    p_user_id uuid
)
returns table (
    admission_offer_event_ticket_type_id uuid,
    admission_offer_expires_at timestamptz,
    admission_offer_id uuid,
    admission_offer_source text,
    admission_offer_status text,
    attendee_checked_in boolean,
    attendee_manually_invited boolean,
    attendee_status text,
    event_purchase_id uuid,
    invitation_request_status text,
    latest_offer_expired boolean,
    purchase_hold_expires_at timestamptz,
    purchase_status text,
    refund_request_status text,
    state text,
    waitlisted boolean
) as $$
    with
    attendee as (
        select ea.checked_in, ea.manually_invited, ea.status
        from event_attendee ea
        where ea.event_id = p_event_id
        and ea.user_id = p_user_id
    ),
    -- Newest claimable offer, ignoring offers whose purchase is being refunded
    active_offer as (
        select
            ao.admission_offer_id,
            ao.event_ticket_type_id,
            ao.expires_at,
            ao.source,
            ao.status
        from admission_offer ao
        where ao.event_id = p_event_id
        and ao.user_id = p_user_id
        and admission_offer_is_active(ao.status)
        and ao.expires_at > current_timestamp
        and not exists (
            select 1
            from event_purchase ep
            where ep.admission_offer_id = ao.admission_offer_id
            and ep.status in (
                'refund-pending',
                'refund-recovery-pending',
                'refund-requested'
            )
        )
        order by ao.created_at desc, ao.admission_offer_id desc
        limit 1
    ),
    -- Latest offer of any state, to report an elapsed invitation
    latest_offer as (
        select ao.status = 'expired'
            or (
                admission_offer_is_active(ao.status)
                and ao.expires_at <= current_timestamp
            ) as is_expired
        from admission_offer ao
        where ao.event_id = p_event_id
        and ao.user_id = p_user_id
        order by ao.created_at desc, ao.admission_offer_id desc
        limit 1
    ),
    -- Resumable pending purchase first, then the newest purchase that still
    -- matters for the seat or its refund
    purchase as (
        select ep.event_purchase_id, ep.hold_expires_at, ep.status
        from event_purchase ep
        where ep.event_id = p_event_id
        and ep.user_id = p_user_id
        and (
            event_purchase_holds_seat(ep.status)
            or ep.status = 'refunded'
            or (ep.status = 'pending' and ep.hold_expires_at > current_timestamp)
        )
        order by
            case when ep.status = 'pending' then 0 else 1 end,
            ep.created_at desc,
            ep.event_purchase_id desc
        limit 1
    ),
    refund_request as (
        select err.status
        from event_refund_request err
        join purchase p using (event_purchase_id)
        where err.status in ('approved', 'approving', 'pending', 'rejected')
        order by err.created_at desc, err.event_refund_request_id desc
        limit 1
    ),
    invitation_request as (
        select eir.status
        from event_invitation_request eir
        where eir.event_id = p_event_id
        and eir.user_id = p_user_id
    ),
    waitlist as (
        select exists (
            select 1
            from event_waitlist ew
            where ew.event_id = p_event_id
            and ew.user_id = p_user_id
        ) as waitlisted
    )
    select
        ao.event_ticket_type_id,
        ao.expires_at,
        ao.admission_offer_id,
        ao.source,
        ao.status,
        coalesce(a.checked_in, false),
        coalesce(a.manually_invited, false),
        a.status,
        p.event_purchase_id,
        ir.status,
        coalesce(lo.is_expired, false),
        p.hold_expires_at,
        p.status,
        rr.status,
        case
            when a.status = 'confirmed' then 'confirmed'
            when p.status = 'pending' then 'payment-pending'
            when ao.admission_offer_id is not null then 'offer-active'
            when a.status = 'registration-questions-pending' then 'registration-pending'
            when a.status = 'invitation-pending' then 'invitation-pending'
            when a.status = 'invitation-rejected' then 'invitation-declined'
            when ir.status = 'pending' then 'approval-pending'
            when ir.status = 'rejected' then 'approval-rejected'
            when w.waitlisted then 'waitlisted'
            when lo.is_expired then 'offer-expired'
            else 'none'
        end,
        w.waitlisted
    from waitlist w
    left join attendee a on true
    left join active_offer ao on true
    left join latest_offer lo on true
    left join purchase p on true
    left join refund_request rr on true
    left join invitation_request ir on true;
$$ language sql stable;
