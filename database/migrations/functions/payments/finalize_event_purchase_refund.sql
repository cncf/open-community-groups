-- Finalizes a provider-complete refund and its local attendance state.
create or replace function finalize_event_purchase_refund(
    p_event_purchase_refund_id uuid,
    p_claim_id uuid,
    p_notification_template_data jsonb
)
returns void as $$
declare
    v_community_id uuid;
    v_event_discount_code_id uuid;
    v_event_id uuid;
    v_group_id uuid;
    v_refund event_purchase_refund;
    v_user_id uuid;
begin
    -- Require the durable notification payload before mutating refund state
    if p_notification_template_data is null then
        raise exception 'refund notification template data is required';
    end if;

    -- Resolve the owning event before taking lifecycle locks
    select ep.event_id
    into v_event_id
    from event_purchase_refund epr
    join event_purchase ep on ep.event_purchase_id = epr.event_purchase_id
    where epr.event_purchase_refund_id = p_event_purchase_refund_id;

    if not found then
        raise exception 'event purchase refund not found';
    end if;

    -- Lock the event before its purchase and durable refund
    perform 1
    from event
    where event_id = v_event_id
    for update;

    select
        g.community_id,
        ep.event_discount_code_id,
        g.group_id,
        ep.user_id
    into
        v_community_id,
        v_event_discount_code_id,
        v_group_id,
        v_user_id
    from event_purchase_refund epr
    join event_purchase ep on ep.event_purchase_id = epr.event_purchase_id
    join event e on e.event_id = ep.event_id
    join "group" g on g.group_id = e.group_id
    where epr.event_purchase_refund_id = p_event_purchase_refund_id
    for update of ep, epr;

    if not found then
        raise exception 'event purchase not found';
    end if;

    -- Load the locked durable refund state used by finalization
    select epr.*
    into v_refund
    from event_purchase_refund epr
    where epr.event_purchase_refund_id = p_event_purchase_refund_id;

    if v_refund.status = 'finalized' then
        return;
    end if;

    if v_refund.claim_id is distinct from p_claim_id
       or v_refund.provider_refunded_at is null then
        raise exception 'event purchase refund claim is not provider-complete';
    end if;

    -- Preserve the attendee relationship while removing active access and capacity
    update event_attendee
    set
        attendance_canceled_at = current_timestamp,
        attendance_canceled_by_user_id = v_refund.initiated_by_user_id,
        checked_in = false,
        checked_in_at = null,
        status = 'attendance-canceled'
    where event_id = v_event_id
    and user_id = v_user_id
    and status in ('confirmed', 'registration-questions-pending');

    -- Mark the purchase refunded and return any discount inventory
    update event_purchase
    set
        refunded_at = current_timestamp,
        status = 'refunded',
        updated_at = current_timestamp
    where event_purchase_id = v_refund.event_purchase_id;

    if v_refund.kind <> 'automatic-unfulfillable-checkout'
       and v_event_discount_code_id is not null then
        perform release_event_discount_code_availability(v_event_discount_code_id);
    end if;

    -- Finalize an attached approving request with the queued review decision
    if v_refund.event_refund_request_id is not null then
        update event_refund_request
        set
            review_note = v_refund.review_note,
            reviewed_at = coalesce(reviewed_at, current_timestamp),
            reviewed_by_user_id = coalesce(
                reviewed_by_user_id,
                v_refund.initiated_by_user_id
            ),
            status = 'approved',
            updated_at = current_timestamp
        where event_refund_request_id = v_refund.event_refund_request_id
        and status = 'approving';
    end if;

    -- Complete the durable job only for the current worker claim
    update event_purchase_refund
    set
        claim_id = null,
        claimed_at = null,
        failure_message = null,
        finalized_at = current_timestamp,
        status = 'finalized',
        updated_at = current_timestamp
    where event_purchase_refund_id = p_event_purchase_refund_id
    and claim_id = p_claim_id;

    if not found then
        raise exception 'event purchase refund claim is no longer current';
    end if;

    -- Record the completed refund for reconciliation and support work
    perform insert_audit_log(
        'event_refunded',
        v_refund.initiated_by_user_id,
        'event',
        v_event_id,
        v_community_id,
        v_group_id,
        v_event_id,
        jsonb_build_object(
            'event_purchase_id', v_refund.event_purchase_id,
            'kind', v_refund.kind,
            'provider_refund_id', v_refund.provider_refund_id,
            'user_id', v_user_id
        )
    );

    -- Enqueue refund completion in the same transaction as finalization
    perform enqueue_notification(
        'event-refund-approved',
        p_notification_template_data,
        '[]'::jsonb,
        array[v_user_id]
    );
end;
$$ language plpgsql;
