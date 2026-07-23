-- Returns whether an event can be deleted or must first be canceled or settled.
create or replace function get_event_delete_eligibility(
    p_group_id uuid,
    p_event_id uuid
)
returns text as $$
    select case
        -- Prevent deletion while a checkout or refund can still progress
        when exists (
            select 1
            from event_purchase ep
            where ep.event_id = e.event_id
            and (
                -- A pending checkout may still become a completed purchase
                (
                    ep.status = 'pending'
                    and (
                        ep.hold_expires_at > current_timestamp
                        or ep.provider_checkout_session_id is not null
                    )
                )
                -- These purchase states still require refund processing
                or ep.status in (
                    'refund-pending',
                    'refund-recovery-pending',
                    'refund-requested'
                )
            )
        )
        -- A durable refund remains active until finalized or recovered
        or exists (
            select 1
            from event_purchase ep
            join event_purchase_refund epr using (event_purchase_id)
            where ep.event_id = e.event_id
            and epr.status <> 'finalized'
            and epr.recovery_completed_at is null
        ) then 'refunds-pending'
        -- Canceled events have already completed the required workflow
        when e.canceled then 'allowed'
        -- Past events no longer need cancellation before deletion
        when coalesce(e.ends_at, e.starts_at) < current_timestamp then 'allowed'
        -- Unused drafts have no lifecycle records that deletion could orphan
        when not e.published
             and e.published_at is null
             and not exists (
                 select 1
                 from audit_log al
                 where al.event_id = e.event_id
                 and al.action = 'event_published'
             )
             and not exists (
                 select 1 from event_attendee ea where ea.event_id = e.event_id
             )
             and not exists (
                 select 1 from event_invitation_request eir where eir.event_id = e.event_id
             )
             and not exists (
                 select 1 from event_purchase ep where ep.event_id = e.event_id
             )
             and not exists (
                 select 1 from event_waitlist ew where ew.event_id = e.event_id
             ) then 'allowed'
        -- Active, published, or used events must be canceled first
        else 'cancel-first'
    end
    from event e
    where e.event_id = p_event_id
    and e.group_id = p_group_id
    and e.deleted = false;
$$ language sql;
