-- cancel_event marks an event as canceled while preserving public visibility.
create or replace function cancel_event(
    p_actor_user_id uuid,
    p_group_id uuid,
    p_event_id uuid
)
returns void as $$
declare
    v_event event;
    v_event_purchase_id uuid;
    v_purchase event_purchase;
begin
    -- Lock the event, if not deleted or canceled, to serialize state transitions
    v_event := lock_manageable_event(p_group_id, p_event_id, false);

    -- Reject events that are already over
    if event_is_past(v_event) then
        raise exception 'event not found or inactive' using errcode = 'OCG01';
    end if;

    -- Close pending and approved co-host invitations before canceling the event
    perform close_event_cohosts(p_actor_user_id, p_event_id, 'event-canceled');

    -- Cancel active offers, expire checkouts, and clear enrollment queues
    perform close_event_enrollment(p_actor_user_id, p_event_id);

    -- Lock refundable purchases after the event so attendee requests cannot race cancellation
    perform 1
    from event_purchase
    where event_id = p_event_id
    and status in ('completed', 'refund-requested')
    order by event_purchase_id
    for update;

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

    -- Withdraw invitations that were never answered
    update event_attendee
    set status = 'invitation-canceled'
    where event_id = p_event_id
    and status = 'invitation-pending';

    -- Refund free and external ticket purchases locally in lock order
    for v_event_purchase_id in
        select ep.event_purchase_id
        from event_purchase ep
        where ep.event_id = p_event_id
        and (
            ep.amount_minor = 0
            or ep.charge_model = 'external'
        )
        and ep.status in ('completed', 'refund-requested')
        order by ep.event_purchase_id
    loop
        -- Close the purchase, its discount reservation and any waiting request
        perform refund_event_purchase_locally(v_event_purchase_id, p_actor_user_id);
    end loop;

    -- Queue provider-backed purchases in lock order
    for v_purchase in
        select ep.*
        from event_purchase ep
        where ep.event_id = p_event_id
        and ep.amount_minor > 0
        and ep.charge_model is distinct from 'external'
        and ep.status in ('completed', 'refund-requested')
        order by ep.event_purchase_id
    loop
        -- Link the waiting request and skip purchases that already have durable work
        perform enqueue_event_purchase_refund(
            v_purchase,
            'event-cancellation',
            v_purchase.provider_total_minor,
            (
                select err.event_refund_request_id
                from event_refund_request err
                where err.event_purchase_id = v_purchase.event_purchase_id
                and err.status in ('approving', 'pending')
            ),
            p_actor_user_id
        );
    end loop;

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
    and ep.charge_model is distinct from 'external'
    and err.status = 'pending';

    -- Hand provider-backed purchases to their durable refund jobs
    update event_purchase
    set
        hold_expires_at = null,
        status = 'refund-pending',
        updated_at = current_timestamp
    where event_id = p_event_id
    and amount_minor > 0
    and charge_model is distinct from 'external'
    and status in ('completed', 'refund-requested');

    -- Mark the event as canceled
    update event set canceled = true
    where event_id = p_event_id
    and group_id = p_group_id
    and canceled = false
    and deleted = false;

    -- Request provider deletion of the event and session meetings
    perform mark_event_meetings_out_of_sync(p_event_id);

    -- Track the event cancellation
    perform insert_audit_log(
        'event_canceled',
        p_actor_user_id,
        'event',
        p_event_id,
        p_group_id => p_group_id,
        p_event_id => p_event_id
    );
end;
$$ language plpgsql;
