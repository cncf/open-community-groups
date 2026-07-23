-- cancel_event marks an event as canceled while preserving public visibility.
create or replace function cancel_event(
    p_actor_user_id uuid,
    p_group_id uuid,
    p_event_id uuid
)
returns void as $$
declare
    v_event_discount_code_id uuid;
begin
    -- Lock event row to serialize state transitions
    perform 1
    from event
    where event_id = p_event_id
    and group_id = p_group_id
    and canceled = false
    and deleted = false
    and (
        coalesce(ends_at, starts_at) is null
        or coalesce(ends_at, starts_at) >= current_timestamp
    )
    for update;

    if not found then
        raise exception 'event not found or inactive';
    end if;

    -- Lock refundable purchases after the event so attendee requests cannot race cancellation
    perform 1
    from event_purchase
    where event_id = p_event_id
    and status in ('completed', 'refund-requested')
    order by event_purchase_id
    for update;

    -- Reject paid purchases that cannot be handed to a refund worker
    perform 1
    from event_purchase
    where event_id = p_event_id
    and amount_minor > 0
    and status in ('completed', 'refund-requested')
    and (
        payment_provider_id is null
        or provider_payment_reference is null
    );

    if found then
        raise exception 'event has a paid purchase that is not ready for refund';
    end if;

    -- Preserve attendance history while removing active access and capacity
    update event_attendee
    set
        attendance_canceled_at = current_timestamp,
        attendance_canceled_by_user_id = p_actor_user_id,
        checked_in = false,
        checked_in_at = null,
        status = 'attendance-canceled'
    where event_id = p_event_id
    and status in ('confirmed', 'registration-questions-pending');

    update event_attendee
    set status = 'invitation-canceled'
    where event_id = p_event_id
    and status = 'invitation-pending';

    -- Close free ticket purchases locally and restore discount inventory
    for v_event_discount_code_id in
        update event_purchase
        set
            refunded_at = current_timestamp,
            status = 'refunded',
            updated_at = current_timestamp
        where event_id = p_event_id
        and amount_minor = 0
        and status in ('completed', 'refund-requested')
        returning event_discount_code_id
    loop
        if v_event_discount_code_id is not null then
            perform release_event_discount_code_availability(v_event_discount_code_id);
        end if;
    end loop;

    -- Complete free-purchase refund requests locally without worker handoff
    update event_refund_request err
    set
        reviewed_at = coalesce(err.reviewed_at, current_timestamp),
        reviewed_by_user_id = coalesce(err.reviewed_by_user_id, p_actor_user_id),
        status = 'approved',
        updated_at = current_timestamp
    from event_purchase ep
    where ep.event_purchase_id = err.event_purchase_id
    and ep.event_id = p_event_id
    and ep.amount_minor = 0
    and ep.status = 'refunded'
    and err.status in ('approving', 'pending');

    -- Queue provider-backed purchases that do not already have durable work
    insert into event_purchase_refund (
        amount_minor,
        currency_code,
        event_purchase_id,
        event_refund_request_id,
        idempotency_key,
        initiated_by_user_id,
        kind,
        payment_provider_id,
        status
    )
    select
        ep.amount_minor,
        ep.currency_code,
        ep.event_purchase_id,
        err.event_refund_request_id,
        format('event-purchase-refund-%s', ep.event_purchase_id),
        p_actor_user_id,
        'event-cancellation',
        ep.payment_provider_id,
        'provider-pending'
    from event_purchase ep
    left join event_refund_request err
        on err.event_purchase_id = ep.event_purchase_id
        and err.status in ('approving', 'pending')
    where ep.event_id = p_event_id
    and ep.amount_minor > 0
    and ep.status in ('completed', 'refund-requested')
    on conflict (event_purchase_id) do nothing;

    -- Move attached paid requests into the worker-owned approval state
    update event_refund_request err
    set
        reviewed_at = coalesce(err.reviewed_at, current_timestamp),
        reviewed_by_user_id = coalesce(err.reviewed_by_user_id, p_actor_user_id),
        status = 'approving',
        updated_at = current_timestamp
    from event_purchase ep
    where ep.event_purchase_id = err.event_purchase_id
    and ep.event_id = p_event_id
    and ep.amount_minor > 0
    and err.status = 'pending';

    -- Hand provider-backed purchases to their durable refund jobs
    update event_purchase
    set
        hold_expires_at = null,
        status = 'refund-pending',
        updated_at = current_timestamp
    where event_id = p_event_id
    and amount_minor > 0
    and status in ('completed', 'refund-requested');

    -- Update event to mark as canceled
    -- If meeting was requested, mark meeting_in_sync as false to trigger deletion
    update event set
        canceled = true,
        meeting_in_sync = case
            when meeting_requested = true then false
            else meeting_in_sync
        end
    where event_id = p_event_id
    and group_id = p_group_id
    and canceled = false
    and deleted = false;

    -- Mark sessions as out of sync to trigger meeting deletion
    update session set meeting_in_sync = false
    where event_id = p_event_id
    and meeting_requested = true;

    -- Track the event cancellation
    perform insert_audit_log(
        'event_canceled',
        p_actor_user_id,
        'event',
        p_event_id,
        (select community_id from "group" where group_id = p_group_id),
        p_group_id,
        p_event_id
    );
end;
$$ language plpgsql;
