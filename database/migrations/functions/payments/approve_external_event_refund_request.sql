-- Approves an external-purchase refund request and refunds it locally.
create or replace function approve_external_event_refund_request(
    p_actor_user_id uuid,
    p_group_id uuid,
    p_event_purchase_id uuid,
    p_review_note text,
    p_notification_template_data jsonb default null
)
returns jsonb as $$
declare
    v_charge_model text;
    v_community_id uuid;
    v_event_discount_code_id uuid;
    v_event_id uuid;
    v_event_ticket_type_id uuid;
    v_refund_request_id uuid;
    v_refund_request_status text;
    v_review_note text := nullif(btrim(p_review_note), '');
    v_status text;
    v_user_id uuid;
begin
    -- Lock the group before the event to match dashboard event mutations
    select g.community_id
    into v_community_id
    from "group" g
    where g.group_id = p_group_id
    for update of g;

    -- Reject missing groups after the lock attempt
    if not found then
        raise exception 'refund request not found';
    end if;

    -- Lock the event before ticket types, purchases, and refund requests
    select e.event_id
    into v_event_id
    from event e
    join event_purchase ep on ep.event_id = e.event_id
    where e.group_id = p_group_id
    and ep.event_purchase_id = p_event_purchase_id
    for update of e;

    -- Reject purchases outside the requested group
    if not found then
        raise exception 'refund request not found';
    end if;

    -- Lock ticket tiers before serializing this attendee's enrollment state
    perform 1
    from event_ticket_type ett
    where ett.event_id = v_event_id
    order by ett.event_ticket_type_id
    for update of ett;

    -- Lock and load the purchase before its refund request
    select
        ep.charge_model,
        ep.event_discount_code_id,
        ep.event_ticket_type_id,
        ep.status,
        ep.user_id
    into
        v_charge_model,
        v_event_discount_code_id,
        v_event_ticket_type_id,
        v_status,
        v_user_id
    from event_purchase ep
    where ep.event_purchase_id = p_event_purchase_id
    and ep.event_id = v_event_id
    for update of ep;

    -- Reject purchases that disappeared while waiting for the lock
    if not found then
        raise exception 'refund request not found';
    end if;

    -- Reject non-external purchases that must be approved through the provider
    if v_charge_model <> 'external' then
        raise exception 'only external purchases can be refunded locally';
    end if;

    -- Reconcile leftover pending requests after a local external refund
    if v_status = 'refunded' then
        update event_refund_request
        set
            review_note = coalesce(v_review_note, review_note),
            reviewed_at = coalesce(reviewed_at, current_timestamp),
            reviewed_by_user_id = coalesce(reviewed_by_user_id, p_actor_user_id),
            status = 'approved',
            updated_at = current_timestamp
        where event_purchase_id = p_event_purchase_id
        and status = 'pending';

        -- Return early on idempotent replays of an already refunded purchase
        return jsonb_build_object(
            'community_id', v_community_id,
            'event_id', v_event_id,
            'transitioned', false,
            'user_id', v_user_id
        );
    end if;

    -- Reject purchases that are not waiting for organizer approval
    if v_status <> 'refund-requested' then
        raise exception 'refund request not found';
    end if;

    -- Serialize this attendee's enrollment transitions
    perform pg_advisory_xact_lock(hashtext(v_event_id::text), hashtext(v_user_id::text));

    -- Lock the current refund request after its purchase
    select
        err.event_refund_request_id,
        err.status
    into
        v_refund_request_id,
        v_refund_request_status
    from event_refund_request err
    where err.event_purchase_id = p_event_purchase_id
    and err.status in ('approved', 'pending')
    for update;

    -- Reject refund requests that changed while waiting for their lock
    if not found then
        raise exception 'refund request not found';
    end if;

    -- Return early on idempotent replays of an already approved request
    if v_refund_request_status = 'approved' then
        return jsonb_build_object(
            'community_id', v_community_id,
            'event_id', v_event_id,
            'transitioned', false,
            'user_id', v_user_id
        );
    end if;

    -- Persist the review decision on the refund request
    update event_refund_request
    set
        review_note = v_review_note,
        reviewed_at = current_timestamp,
        reviewed_by_user_id = p_actor_user_id,
        status = 'approved',
        updated_at = current_timestamp
    where event_refund_request_id = v_refund_request_id
    and status = 'pending';

    -- Reject requests that left the pending state
    if not found then
        raise exception 'refund request not found';
    end if;

    -- Mark the external purchase refunded without creating provider work
    update event_purchase
    set
        refunded_at = current_timestamp,
        status = 'refunded',
        updated_at = current_timestamp
    where event_purchase_id = p_event_purchase_id;

    -- Release any reserved discount redemption after refunding the purchase
    if v_event_discount_code_id is not null then
        perform release_event_discount_code_availability(v_event_discount_code_id);
    end if;

    -- Preserve the attendee row unless a replacement purchase still occupies the seat
    update event_attendee
    set
        attendance_canceled_at = current_timestamp,
        attendance_canceled_by_user_id = p_actor_user_id,
        checked_in = false,
        checked_in_at = null,
        status = 'attendance-canceled'
    where event_id = v_event_id
    and user_id = v_user_id
    and status in ('confirmed', 'registration-questions-pending')
    and not exists (
        select 1
        from event_purchase replacement
        where replacement.event_id = v_event_id
        and replacement.event_purchase_id <> p_event_purchase_id
        and replacement.status in ('completed', 'refund-requested')
        and replacement.user_id = v_user_id
    );

    -- Reconcile the released ticket-tier capacity
    perform reconcile_event_enrollment(v_event_id, v_event_ticket_type_id);

    -- Record the organizer action after the state transition succeeds
    perform insert_audit_log(
        'event_refund_approved',
        p_actor_user_id,
        'event',
        v_event_id,
        v_community_id,
        p_group_id,
        v_event_id,
        jsonb_build_object(
            'event_purchase_id', p_event_purchase_id,
            'user_id', v_user_id
        )
    );

    -- Enqueue the refund-approved notification in the same transaction
    if p_notification_template_data is not null then
        perform enqueue_notification(
            'event-refund-approved',
            p_notification_template_data,
            '[]'::jsonb,
            array[v_user_id]
        );
    end if;

    -- Return the identifiers needed by the caller after approval
    return jsonb_build_object(
        'community_id', v_community_id,
        'event_id', v_event_id,
        'transitioned', true,
        'user_id', v_user_id
    );
end;
$$ language plpgsql;
