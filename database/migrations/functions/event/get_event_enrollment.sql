-- Returns the user's current enrollment state for an attendee-visible event.
create or replace function get_event_enrollment(
    p_community_id uuid,
    p_event_id uuid,
    p_user_id uuid
)
returns json as $$
    with
    -- Scope every downstream state lookup to an attendee-visible event.
    scoped_event as (
        select e.attendee_approval_required
        from event e
        join "group" g using (group_id)
        where e.event_id = p_event_id
        and g.community_id = p_community_id
        and g.active = true
        and e.deleted = false
        and e.published = true
        and (e.canceled = true or e.ends_at is null or e.ends_at >= current_timestamp)
    ),
    -- Resolve the newest claimable offer while suppressing refunding purchases.
    active_offer as (
        select ao.admission_offer_id, ao.event_ticket_type_id, ao.source
        from admission_offer ao
        where ao.event_id = p_event_id
        and ao.user_id = p_user_id
        and ao.status in ('checkout_pending', 'pending')
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
        and exists (select 1 from scoped_event)
        order by ao.created_at desc, ao.admission_offer_id desc
        limit 1
    ),
    -- Preserve the latest terminal or elapsed offer state for attendee feedback.
    latest_offer as (
        select ao.status = 'expired'
            or (
                ao.status in ('checkout_pending', 'pending')
                and ao.expires_at <= current_timestamp
            ) as is_expired
        from admission_offer ao
        where ao.event_id = p_event_id
        and ao.user_id = p_user_id
        and exists (select 1 from scoped_event)
        order by ao.created_at desc, ao.admission_offer_id desc
        limit 1
    ),
    -- Prefer resumable checkout state before completed attendee purchases.
    purchase_state as (
        select ep.amount_minor, ep.event_purchase_id, ep.provider_checkout_url
        from event_purchase ep
        where ep.event_id = p_event_id
        and ep.user_id = p_user_id
        and (
            ep.status in ('completed', 'refund-requested')
            or (ep.status = 'pending' and ep.hold_expires_at > current_timestamp)
        )
        and exists (select 1 from scoped_event)
        order by
            case when ep.status = 'pending' then 0 else 1 end,
            ep.created_at desc,
            ep.event_purchase_id desc
        limit 1
    ),
    -- Apply the canonical enrollment-state precedence across normalized tables.
    enrollment_state as (
        select
            coalesce((
                select bool_and(ea.checked_in)
                from event_attendee ea
                where ea.event_id = p_event_id
                and ea.user_id = p_user_id
                and ea.status = 'confirmed'
                and exists (select 1 from scoped_event)
            ), false) as is_checked_in,
            coalesce((
                select bool_or(ea.manually_invited)
                from event_attendee ea
                where ea.event_id = p_event_id
                and ea.user_id = p_user_id
                and exists (select 1 from scoped_event)
            ), false)
            or exists (
                select 1
                from active_offer ao
                where ao.source = 'organizer_invitation'
            ) as manually_invited,
            case
                when exists (
                    select 1
                    from event_attendee ea
                    where ea.event_id = p_event_id
                    and ea.user_id = p_user_id
                    and ea.status = 'confirmed'
                    and exists (select 1 from scoped_event)
                ) then 'attendee'
                when exists (select 1 from purchase_state) and exists (
                    select 1
                    from event_purchase ep
                    join purchase_state ps using (event_purchase_id)
                    where ep.status = 'pending'
                ) then 'pending-payment'
                when exists (select 1 from active_offer) then 'invitation-approved'
                when exists (
                    select 1
                    from event_invitation_request eir
                    where eir.event_id = p_event_id
                    and eir.user_id = p_user_id
                    and eir.status = 'pending'
                    and (select attendee_approval_required from scoped_event)
                ) then 'pending-approval'
                when exists (
                    select 1
                    from event_invitation_request eir
                    where eir.event_id = p_event_id
                    and eir.user_id = p_user_id
                    and eir.status = 'rejected'
                    and (select attendee_approval_required from scoped_event)
                ) then 'rejected'
                when exists (
                    select 1
                    from event_waitlist ew
                    where ew.event_id = p_event_id
                    and ew.user_id = p_user_id
                    and exists (select 1 from scoped_event)
                ) then 'waitlisted'
                when exists (select 1 from latest_offer where is_expired) then 'offer-expired'
                else 'none'
            end as status
    ),
    -- Attach the latest active review state for the selected purchase.
    refund_request_state as (
        select err.status
        from event_refund_request err
        join purchase_state ps using (event_purchase_id)
        where err.status in ('approved', 'approving', 'pending', 'rejected')
        order by err.created_at desc, err.event_refund_request_id desc
        limit 1
    )
    -- Project the normalized state into the Rust enrollment JSON contract.
    select (
        jsonb_build_object(
            'is_checked_in', es.is_checked_in,
            'purchase_amount_minor', (select amount_minor from purchase_state),
            'refund_request_status', (select status from refund_request_state),
            'resume_checkout_url', (select provider_checkout_url from purchase_state),
            'status', es.status
        )
        || jsonb_strip_nulls(jsonb_build_object(
            'admission_offer_id', (select admission_offer_id from active_offer),
            'event_ticket_type_id', (select event_ticket_type_id from active_offer)
        ))
        || case
            when es.manually_invited then jsonb_build_object('manually_invited', true)
            else '{}'::jsonb
        end
    )::json
    from enrollment_state es;
$$ language sql;
