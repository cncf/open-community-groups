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
    v_existing_refund_kind text;
    v_purchase event_purchase;
    v_refund_request_id uuid;
begin
    -- Lock the event and verify it belongs to the selected group and can be changed
    select g.community_id
    into v_community_id
    from event e
    join "group" g using (group_id)
    where e.event_id = p_event_id
    and e.group_id = p_group_id
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

    -- Lock ticket tiers before serializing this attendee's enrollment state
    perform 1
    from event_ticket_type ett
    where ett.event_id = p_event_id
    order by ett.event_ticket_type_id
    for update of ett;

    -- Serialize this attendee's enrollment transitions
    perform pg_advisory_xact_lock(hashtext(p_event_id::text), hashtext(p_user_id::text));

    -- Require active attendance before changing or refunding it
    perform 1
    from event_attendee ea
    where ea.event_id = p_event_id
    and ea.user_id = p_user_id
    and ea.status = 'confirmed'
    for update of ea;

    if not found then
        raise exception 'confirmed event attendee not found';
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

    -- Queue paid cancellations without releasing attendance or capacity
    if found and v_purchase.amount_minor > 0 then
        -- Preserve an already queued attendee refund on idempotent retries
        select epr.kind
        into v_existing_refund_kind
        from event_purchase_refund epr
        where epr.event_purchase_id = v_purchase.event_purchase_id
        for update;

        -- Validate and reuse existing durable refund work
        if found then
            if v_existing_refund_kind not in (
                'attendance-cancellation',
                'refund-request-approval'
            ) then
                raise exception 'event purchase refund already started with different kind';
            end if;

            return json_build_object('cancellation_status', 'refund-queued');
        end if;

        -- Validate the provider contract before creating durable work
        if v_purchase.payment_provider_id is null
           or v_purchase.provider_payment_reference is null then
            raise exception 'paid purchase is not ready for refund';
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

        if v_refund_request_id is null then
            raise exception 'refund request is not available for attendance cancellation';
        end if;

        -- Insert durable worker work with the purchase-level idempotency key
        insert into event_purchase_refund (
            amount_minor,
            currency_code,
            event_purchase_id,
            idempotency_key,
            kind,
            payment_provider_id,
            status,

            event_refund_request_id,
            initiated_by_user_id
        ) values (
            v_purchase.provider_total_minor,
            v_purchase.currency_code,
            v_purchase.event_purchase_id,
            format('event-purchase-refund-%s', v_purchase.event_purchase_id),
            'attendance-cancellation',
            v_purchase.payment_provider_id,
            'provider-pending',

            v_refund_request_id,
            p_actor_user_id
        );

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
    update event_attendee
    set
        attendance_canceled_at = current_timestamp,
        attendance_canceled_by_user_id = p_actor_user_id,
        checked_in = false,
        checked_in_at = null,
        status = 'attendance-canceled'
    where event_id = p_event_id
    and user_id = p_user_id
    and status = 'confirmed';

    -- If the attendee had a free ticket purchase, delegate the refund transition
    if v_purchase.event_purchase_id is not null then
        perform refund_free_event_purchase(v_purchase.event_purchase_id);
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
