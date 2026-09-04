-- Completes an externally resolved terminal provider refund.
create or replace function complete_event_purchase_refund_recovery(
    p_actor_user_id uuid,
    p_group_id uuid,
    p_event_purchase_refund_id uuid,
    p_recovery_reference text,
    p_recovery_note text,
    p_notification_template_data jsonb,
    p_configured_provider text default null
)
returns jsonb as $$
declare
    v_event event;
    v_group "group";
    v_locked record;
    v_purchase event_purchase;
    v_refund event_purchase_refund;
begin
    -- Validate the operator and required recovery evidence
    if p_actor_user_id is null then
        raise exception 'actor user id is required';
    end if;

    -- Require the group scope of the dashboard route
    if p_group_id is null then
        raise exception 'group id is required';
    end if;

    -- Require the external reference proving the refund was issued
    if nullif(btrim(p_recovery_reference), '') is null then
        raise exception 'recovery reference is required' using errcode = 'OCG01';
    end if;

    -- Require the operator note explaining the recovery
    if nullif(btrim(p_recovery_note), '') is null then
        raise exception 'recovery note is required' using errcode = 'OCG01';
    end if;

    -- Resolve the purchase and event of the refund within the group before taking locks
    select ep.*
    into v_purchase
    from event_purchase_refund epr
    join event_purchase ep on ep.event_purchase_id = epr.event_purchase_id
    join event e on e.event_id = ep.event_id
    where epr.event_purchase_refund_id = p_event_purchase_refund_id
    and e.group_id = p_group_id;

    -- Reject refunds outside the group
    if not found then
        raise exception 'event purchase refund not found' using errcode = 'OCG01';
    end if;

    -- Lock the event before its purchase and durable refund
    perform 1
    from event e
    where e.event_id = v_purchase.event_id
    for update of e;

    -- Reconcile and serialize enrollment before locking recovery state
    perform reconcile_event_enrollment(
        v_purchase.event_id,
        v_purchase.event_ticket_type_id,
        p_configured_provider
    );

    perform pg_advisory_xact_lock(hashtext(v_purchase.event_id::text), hashtext(v_purchase.user_id::text));

    -- Lock the purchase and refund and load the event and group they belong to
    select ep, epr, e, g
    into v_locked
    from event_purchase_refund epr
    join event_purchase ep on ep.event_purchase_id = epr.event_purchase_id
    join event e on e.event_id = ep.event_id
    join "group" g on g.group_id = e.group_id
    where epr.event_purchase_refund_id = p_event_purchase_refund_id
    and e.group_id = p_group_id
    for update of ep, epr;

    -- Reject refunds that left the group while waiting for the locks
    if not found then
        raise exception 'recoverable event purchase refund not found' using errcode = 'OCG01';
    end if;

    v_event := v_locked.e;
    v_group := v_locked.g;
    v_purchase := v_locked.ep;
    v_refund := v_locked.epr;

    -- Treat an exact repeated completion as an idempotent operator retry
    if v_refund.recovery_completed_at is not null then
        -- Reject a repeated completion carrying different evidence
        if v_refund.recovery_completed_by_user_id <> p_actor_user_id
           or v_refund.recovery_note <> btrim(p_recovery_note)
           or v_refund.recovery_reference <> btrim(p_recovery_reference) then
            raise exception 'refund recovery already completed with different evidence' using errcode = 'OCG01';
        end if;

        return jsonb_build_object(
            'event_id', v_event.event_id,
            'recovered_now', false,
            'user_id', v_purchase.user_id
        );
    end if;

    -- Only terminally failed provider refunds with a provider reference are recoverable
    if v_refund.status <> 'provider-failed'
       or not v_refund.terminal_failure
       or v_refund.provider_refund_id is null then
        raise exception 'recoverable event purchase refund not found' using errcode = 'OCG01';
    end if;

    -- Validate the local lifecycle that the external recovery will complete
    if v_refund.finalized_at is null then
        -- Automatic refunds recover purchases still awaiting the provider refund
        if v_refund.kind in ('automatic-unfulfillable-checkout', 'event-cancellation') then
            -- Reject purchases outside the refund-pending state
            if v_purchase.status <> 'refund-pending' then
                raise exception 'recoverable event purchase refund not found' using errcode = 'OCG01';
            end if;

        -- Attendee-driven refunds recover requested purchases, or pending ones on canceled events
        elsif v_refund.kind in ('attendance-cancellation', 'refund-request-approval') then
            -- Reject purchases outside the states those refunds leave behind
            if v_purchase.status <> 'refund-requested'
               and not (v_purchase.status = 'refund-pending' and v_event.canceled) then
                raise exception 'recoverable event purchase refund not found' using errcode = 'OCG01';
            end if;

        -- Reject refund kinds without a local finalization path
        else
            raise exception 'recoverable event purchase refund not found' using errcode = 'OCG01';
        end if;

        -- Lock the approving refund request the recovery finalizes
        if v_refund.event_refund_request_id is not null then
            perform 1
            from event_refund_request err
            where err.event_refund_request_id = v_refund.event_refund_request_id
            and err.event_purchase_id = v_purchase.event_purchase_id
            and err.status = 'approving'
            for update of err;

            -- Reject requests that already left the approving state
            if not found then
                raise exception 'recoverable event purchase refund not found' using errcode = 'OCG01';
            end if;
        end if;

    -- Finalized refunds only recover purchases that already left their seat
    elsif v_purchase.status not in ('refund-recovery-pending', 'refunded') then
        raise exception 'recoverable event purchase refund not found' using errcode = 'OCG01';
    end if;

    -- Require app-composed notification data before first-time finalization
    if v_refund.finalized_at is null and p_notification_template_data is null then
        raise exception 'refund notification template data is required';
    end if;

    -- Apply local finalization that did not happen before the terminal failure
    if v_refund.finalized_at is null then
        -- Cancel the attendance an attendee-driven refund releases, unless a replacement purchase holds it
        if v_refund.kind in ('attendance-cancellation', 'refund-request-approval') then
            update event_attendee
            set
                attendance_canceled_at = current_timestamp,
                attendance_canceled_by_user_id = case
                    -- Attribute attendee cancellations to the attendee who requested them
                    when v_refund.kind = 'attendance-cancellation'
                        then coalesce(v_refund.initiated_by_user_id, p_actor_user_id)
                    -- Attribute approved refund requests to the operator
                    else p_actor_user_id
                end,
                checked_in = false,
                checked_in_at = null,
                status = 'attendance-canceled'
            where event_id = v_event.event_id
            and user_id = v_purchase.user_id
            and status in ('confirmed', 'registration-questions-pending')
            and not exists (
                select 1
                from event_purchase replacement
                where replacement.event_id = v_event.event_id
                and replacement.event_purchase_id <> v_purchase.event_purchase_id
                and replacement.status in ('completed', 'refund-requested')
                and replacement.user_id = v_purchase.user_id
            );
        end if;

        -- Restore the discount inventory held by refunded seats
        if v_refund.kind in ('attendance-cancellation', 'event-cancellation', 'refund-request-approval')
           and v_purchase.event_discount_code_id is not null then
            perform release_event_discount_code_availability(v_purchase.event_discount_code_id);
        end if;

        -- Approve the refund request the recovery completes
        if v_refund.event_refund_request_id is not null then
            update event_refund_request
            set
                review_note = case
                    -- Record the operator note as the review of an approved request
                    when v_refund.kind = 'refund-request-approval' then btrim(p_recovery_note)
                    -- Keep the review note of other refund kinds
                    else review_note
                end,
                reviewed_at = coalesce(reviewed_at, current_timestamp),
                reviewed_by_user_id = coalesce(reviewed_by_user_id, p_actor_user_id),
                status = 'approved',
                updated_at = current_timestamp
            where event_refund_request_id = v_refund.event_refund_request_id
            and status = 'approving';
        end if;
    end if;

    -- Preserve the failed provider attempt and append the external recovery evidence
    update event_purchase_refund
    set
        finalized_at = coalesce(finalized_at, current_timestamp),
        recovery_completed_at = current_timestamp,
        recovery_completed_by_user_id = p_actor_user_id,
        recovery_note = btrim(p_recovery_note),
        recovery_reference = btrim(p_recovery_reference),
        updated_at = current_timestamp
    where event_purchase_refund_id = p_event_purchase_refund_id;

    -- Mark the purchase refunded
    update event_purchase
    set
        refunded_at = coalesce(refunded_at, current_timestamp),
        status = 'refunded',
        updated_at = current_timestamp
    where event_purchase_id = v_purchase.event_purchase_id;

    -- Fill capacity released only after recovery is locally terminal
    perform reconcile_event_enrollment(
        v_event.event_id,
        v_purchase.event_ticket_type_id,
        p_configured_provider
    );

    -- Record the immutable operator action with the external evidence
    perform insert_audit_log(
        'event_refund_recovery_completed',
        p_actor_user_id,
        'event',
        v_event.event_id,
        v_group.community_id,
        v_event.group_id,
        v_event.event_id,
        jsonb_build_object(
            'event_purchase_id', v_purchase.event_purchase_id,
            'event_purchase_refund_id', p_event_purchase_refund_id,
            'provider_refund_id', v_refund.provider_refund_id,
            'recovery_note', btrim(p_recovery_note),
            'recovery_reference', btrim(p_recovery_reference),
            'user_id', v_purchase.user_id
        )
    );

    -- Enqueue completion atomically when recovery performs local finalization
    if v_refund.finalized_at is null then
        perform enqueue_notification(
            'event-refund-approved',
            p_notification_template_data,
            '[]'::jsonb,
            array[v_purchase.user_id]
        );
    end if;

    return jsonb_build_object(
        'event_id', v_event.event_id,
        'recovered_now', true,
        'user_id', v_purchase.user_id
    );
end;
$$ language plpgsql;
