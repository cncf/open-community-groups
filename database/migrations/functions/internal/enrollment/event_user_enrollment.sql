-- Resolves the enrollment facts of a user for an event from every table that
-- records them: attendee row, active admission offer, relevant purchase,
-- refund request, invitation request and waitlist. A refunded purchase stays
-- relevant only until a later attendance supersedes it. Returns the raw facts
-- every caller derives from; callers map them to their own labels and apply
-- their own locks before mutating.
create or replace function event_user_enrollment(
    p_event_id uuid,
    p_user_id uuid
)
returns table (
    admission_offer_event_ticket_type_id uuid,
    admission_offer_id uuid,
    admission_offer_source text,
    attendee_checked_in boolean,
    attendee_manually_invited boolean,
    attendee_status text,
    event_purchase_id uuid,
    invitation_request_status text,
    latest_offer_expired boolean,
    purchase_status text,
    refund_rejection_reason text,
    refund_request_status text,
    waitlisted boolean
) as $$
    with
    -- Attendee row of the user, if any
    attendee as (
        select ea.checked_in, ea.created_at, ea.manually_invited, ea.status
        from event_attendee ea
        where ea.event_id = p_event_id
        and ea.user_id = p_user_id
    ),
    -- Newest claimable offer, ignoring offers whose purchase is being refunded
    active_offer as (
        select
            ao.admission_offer_id,
            ao.event_ticket_type_id,
            ao.source
        from admission_offer ao
        where ao.event_id = p_event_id
        and ao.user_id = p_user_id
        and admission_offer_is_claimable(ao)
        order by ao.created_at desc, ao.admission_offer_id desc
        limit 1
    ),
    -- Latest offer of any state, to report an elapsed invitation
    latest_offer as (
        select ao.status = 'expired'
            or admission_offer_is_lapsed(ao.status, ao.expires_at) as is_expired
        from admission_offer ao
        where ao.event_id = p_event_id
        and ao.user_id = p_user_id
        order by ao.created_at desc, ao.admission_offer_id desc
        limit 1
    ),
    -- Resumable pending purchase first, then the newest purchase that holds
    -- the seat or carries a refund no later attendance superseded. A refunded
    -- purchase is ignored while the user still holds a seat, since refunds
    -- cancel the attendance they release and revived rows keep created_at. It
    -- is also ignored once an attendee row is created after refunded_at, which
    -- every refund transition stamps; updated_at only covers unstamped refunds
    purchase as (
        select ep.event_purchase_id, ep.status
        from event_purchase ep
        where ep.event_id = p_event_id
        and ep.user_id = p_user_id
        and (
            event_purchase_reserves_seat(ep.status, ep.hold_expires_at)
            or (
                ep.status = 'refunded'
                and not exists (
                    select 1
                    from attendee a
                    where a.status in ('confirmed', 'registration-questions-pending')
                    or a.created_at > coalesce(ep.refunded_at, ep.updated_at)
                )
            )
        )
        order by
            case
                -- Prefer the resumable pending purchase
                when ep.status = 'pending' then 0
                -- Rank every other purchase by recency
                else 1
            end,
            ep.created_at desc,
            ep.event_purchase_id desc
        limit 1
    ),
    -- Latest live or rejected refund request of the selected purchase, with
    -- the attendee-visible reason of a rejection
    refund_request as (
        select
            case
                -- Expose the review note only for rejected requests
                when err.status = 'rejected' then nullif(btrim(err.review_note), '')
            end as rejection_reason,
            err.status
        from event_refund_request err
        join purchase p using (event_purchase_id)
        where err.status in ('approved', 'approving', 'pending', 'rejected')
        order by err.created_at desc, err.event_refund_request_id desc
        limit 1
    ),
    -- Invitation request of the user, if any
    invitation_request as (
        select eir.status
        from event_invitation_request eir
        where eir.event_id = p_event_id
        and eir.user_id = p_user_id
    ),
    -- Whether the user is on the waitlist, as a single anchor row
    waitlist as (
        select exists (
            select 1
            from event_waitlist ew
            where ew.event_id = p_event_id
            and ew.user_id = p_user_id
        ) as waitlisted
    )
    -- Combine the facts into a single row
    select
        ao.event_ticket_type_id,
        ao.admission_offer_id,
        ao.source,
        coalesce(a.checked_in, false),
        coalesce(a.manually_invited, false),
        a.status,
        p.event_purchase_id,
        ir.status,
        coalesce(lo.is_expired, false),
        p.status,
        rr.rejection_reason,
        rr.status,
        w.waitlisted
    from waitlist w
    left join attendee a on true
    left join active_offer ao on true
    left join latest_offer lo on true
    left join purchase p on true
    left join refund_request rr on true
    left join invitation_request ir on true;
$$ language sql stable;
