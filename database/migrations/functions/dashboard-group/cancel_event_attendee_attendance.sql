-- Cancels or queues a refund for confirmed attendance from the group dashboard.
create or replace function cancel_event_attendee_attendance(
    p_actor_user_id uuid,
    p_group_id uuid,
    p_event_id uuid,
    p_user_id uuid,
    p_configured_provider text default null
) returns json as $$
declare
    v_community_id uuid;
    v_event event;
    v_existing_refund_kind text;
    v_purchase event_purchase;
    v_refund_request_id uuid;
begin
    -- Lock the event and verify it belongs to the selected group and can be changed
    v_event := lock_active_event(null, p_group_id, p_event_id);

    -- Load group context needed for audit
    select g.community_id
    into v_community_id
    from "group" g
    where g.group_id = v_event.group_id;

    -- Lock ticket tiers before serializing this attendee's enrollment state
    perform lock_event_ticket_types(p_event_id);

    -- Serialize this attendee's enrollment transitions
    perform lock_event_user(p_event_id, p_user_id);

    -- Require active attendance before changing or refunding it
    perform 1
    from event_attendee ea
    where ea.event_id = p_event_id
    and ea.user_id = p_user_id
    and ea.status = 'confirmed'
    for update of ea;

    -- Reject cancellations that no longer have confirmed attendance
    if not found then
        raise exception 'confirmed event attendee not found' using errcode = 'OCG01';
    end if;

    -- Lock the attendee's current purchase when one exists
    select ep.*
    into v_purchase
    from event_purchase ep
    where ep.event_id = p_event_id
    and ep.user_id = p_user_id
    and ep.status in ('completed', 'refund-requested')
    order by ep.created_at desc, ep.event_purchase_id desc
    limit 1
    for update of ep;

    -- Queue Stripe cancellations without releasing attendance or capacity
    if found
       and v_purchase.amount_minor > 0
       and v_purchase.charge_model is distinct from 'external' then
        -- Preserve an already queued attendee refund on idempotent retries
        select epr.kind
        into v_existing_refund_kind
        from event_purchase_refund epr
        where epr.event_purchase_id = v_purchase.event_purchase_id
        for update;

        -- Validate and reuse existing durable refund work
        if found then
            -- Reject durable work created for a different refund kind
            if v_existing_refund_kind not in (
                'attendance-cancellation',
                'refund-request-approval'
            ) then
                raise exception 'event purchase refund already started with different kind' using errcode = 'OCG01';
            end if;

            -- Report the refund work already queued
            return json_build_object('cancellation_status', 'refund-queued');
        end if;

        -- Attach a synthetic organizer decision or promote an existing request
        insert into event_refund_request (
            event_purchase_id,
            requested_by_user_id,
            status,

            requested_reason,
            reviewed_at,
            reviewed_by_user_id
        ) values (
            v_purchase.event_purchase_id,
            p_actor_user_id,
            'approving',

            'Attendance cancellation requested by an organizer',
            current_timestamp,
            p_actor_user_id
        )
        on conflict (event_purchase_id) do update
        set
            review_note = null,
            reviewed_at = current_timestamp,
            reviewed_by_user_id = p_actor_user_id,
            status = 'approving',
            updated_at = current_timestamp
        where event_refund_request.status in ('approving', 'pending', 'rejected')
        returning event_refund_request_id into v_refund_request_id;

        -- Reject requests that cannot be promoted into attendance cancellation
        if v_refund_request_id is null then
            raise exception 'refund request is not available for attendance cancellation' using errcode = 'OCG01';
        end if;

        -- Queue the attendee refund, rejecting purchases whose refund work already exists
        if enqueue_event_purchase_refund(
            v_purchase,
            'attendance-cancellation',
            v_purchase.provider_total_minor,
            v_refund_request_id,
            p_actor_user_id
        ) is null then
            raise exception 'event purchase refund already started' using errcode = 'OCG01';
        end if;

        -- Mark the purchase as awaiting its queued refund
        update event_purchase
        set
            status = 'refund-requested',
            updated_at = current_timestamp
        where event_purchase_id = v_purchase.event_purchase_id;

        -- Return the queued paid cancellation outcome
        return json_build_object('cancellation_status', 'refund-queued');
    end if;

    -- Preserve the attendee row while removing free active attendance
    perform mark_event_attendance_canceled(p_event_id, p_user_id, p_actor_user_id);

    -- Refund free or external purchases locally after attendance is canceled
    if v_purchase.event_purchase_id is not null then
        perform refund_event_purchase_locally(v_purchase.event_purchase_id, p_actor_user_id);
    end if;

    -- Reconcile the released ticket-tier capacity
    perform reconcile_event_enrollment(
        p_event_id,
        v_purchase.event_ticket_type_id,
        p_configured_provider
    );

    -- Track the completed cancellation
    perform insert_audit_log(
        'event_attendee_attendance_canceled',
        p_actor_user_id,
        'user',
        p_user_id,
        v_community_id,
        p_group_id,
        p_event_id,
        jsonb_build_object('event_id', p_event_id, 'user_id', p_user_id)
    );

    -- Return the completed free cancellation outcome
    return json_build_object('cancellation_status', 'attendance-canceled');
end;
$$ language plpgsql;
