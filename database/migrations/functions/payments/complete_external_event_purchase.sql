-- Completes a pending external purchase after an organizer marks it paid.
create or replace function complete_external_event_purchase(
    p_actor_user_id uuid,
    p_group_id uuid,
    p_event_purchase_id uuid,
    p_details text,
    p_notification_attachments jsonb default '[]'::jsonb,
    p_notification_template_data jsonb default null
)
returns jsonb as $$
declare
    v_admission_offer_id uuid;
    v_charge_model text;
    v_community_id uuid;
    v_details text := nullif(btrim(p_details), '');
    v_event_canceled boolean;
    v_event_deleted boolean;
    v_event_ends_at timestamptz;
    v_event_id uuid;
    v_event_published boolean;
    v_event_starts_at timestamptz;
    v_event_ticket_type_id uuid;
    v_group_active boolean;
    v_hold_expires_at timestamptz;
    v_manually_invited boolean;
    v_purchase_group_id uuid;
    v_purchase_hold_expired boolean;
    v_recovery_pending boolean;
    v_status text;
    v_user_id uuid;
begin
    -- Resolve immutable parent identifiers before taking locks
    select
        ep.event_id,
        ep.event_ticket_type_id,
        e.group_id,
        ep.status in ('expired', 'pending')
            and ep.hold_expires_at is not null
            and ep.hold_expires_at <= current_timestamp
    into
        v_event_id,
        v_event_ticket_type_id,
        v_purchase_group_id,
        v_purchase_hold_expired
    from event_purchase ep
    join event e on e.event_id = ep.event_id
    where ep.event_purchase_id = p_event_purchase_id;

    -- Reject purchases that do not exist
    if not found then
        raise exception 'purchase not found';
    end if;

    -- Reject purchases that belong to another group
    if v_purchase_group_id is distinct from p_group_id then
        raise exception 'purchase not found';
    end if;

    -- Reject holds that already expired before locks are taken
    if v_purchase_hold_expired then
        raise exception 'purchase hold has expired';
    end if;

    -- Lock the group before the event to match dashboard event mutations
    select g.active, g.community_id
    into v_group_active, v_community_id
    from "group" g
    where g.group_id = p_group_id
    for update of g;

    -- Reject missing groups after the lock attempt
    if not found then
        raise exception 'purchase not found';
    end if;

    -- Lock the event before the purchase to match checkout and attendance flows
    select
        e.canceled,
        e.deleted,
        e.ends_at,
        e.published,
        e.starts_at
    into
        v_event_canceled,
        v_event_deleted,
        v_event_ends_at,
        v_event_published,
        v_event_starts_at
    from event e
    where e.event_id = v_event_id
    and e.group_id = p_group_id
    for update of e;

    -- Reject events that left the requested group
    if not found then
        raise exception 'purchase not found';
    end if;

    -- Reconcile under the global event, tier, user, and purchase lock order
    perform reconcile_event_enrollment(v_event_id, v_event_ticket_type_id);

    -- Lock the purchase before validating and completing it
    select
        ep.admission_offer_id,
        ep.charge_model,
        ep.hold_expires_at,
        coalesce(ao.source = 'organizer_invitation', false),
        exists (
            select 1
            from event_purchase recovery_ep
            where recovery_ep.event_id = ep.event_id
            and recovery_ep.event_purchase_id <> ep.event_purchase_id
            and recovery_ep.status = 'refund-recovery-pending'
            and recovery_ep.user_id = ep.user_id
        ),
        ep.status,
        ep.user_id
    into
        v_admission_offer_id,
        v_charge_model,
        v_hold_expires_at,
        v_manually_invited,
        v_recovery_pending,
        v_status,
        v_user_id
    from event_purchase ep
    left join admission_offer ao
        on ao.admission_offer_id = ep.admission_offer_id
    where ep.event_purchase_id = p_event_purchase_id
    for update of ep;

    -- Reject purchases removed while waiting for the lock
    if not found then
        raise exception 'purchase not found';
    end if;

    -- Return early on idempotent replays of a completed external purchase
    if v_status = 'completed' and v_charge_model = 'external' then
        return jsonb_build_object(
            'community_id', v_community_id,
            'event_id', v_event_id,
            'transitioned', false,
            'user_id', v_user_id
        );
    end if;

    -- Reject purchases that are not an external pending hold
    if v_charge_model <> 'external' then
        raise exception 'only external purchases can be marked paid locally';
    end if;

    -- Reject purchases that left the pending state
    if v_status <> 'pending' then
        raise exception 'purchase is no longer pending';
    end if;

    -- Reject holds that expired during reconciliation
    if v_hold_expires_at is not null and v_hold_expires_at <= current_timestamp then
        raise exception 'purchase hold has expired';
    end if;

    -- Reject completion while another purchase is in refund recovery
    if v_recovery_pending then
        raise exception 'checkout is unavailable while refund recovery is in progress';
    end if;

    -- Ensure the event is still active before completing the purchase
    if not v_group_active
       or v_event_deleted
       or not v_event_published
       or v_event_canceled
       or (
           coalesce(v_event_ends_at, v_event_starts_at) is not null
           and coalesce(v_event_ends_at, v_event_starts_at) <= current_timestamp
       ) then
        raise exception 'event not found or inactive';
    end if;

    -- Complete the linked reservation before creating active attendance
    if v_admission_offer_id is not null then
        update admission_offer
        set
            status = 'completed',
            updated_at = current_timestamp
        where admission_offer_id = v_admission_offer_id
        and status = 'checkout_pending';

        -- Reject offers that left the checkout-pending state
        if not found then
            raise exception 'admission offer is no longer available';
        end if;
    end if;

    -- Confirm the attendee and persist any pending registration answers
    insert into event_attendee (event_id, user_id, manually_invited)
    values (v_event_id, v_user_id, v_manually_invited)
    on conflict (event_id, user_id) do update
    set
        attendance_canceled_at = null,
        attendance_canceled_by_user_id = null,
        manually_invited = excluded.manually_invited,
        status = 'confirmed'
    where event_attendee.status in (
        'attendance-canceled',
        'confirmed',
        'invitation-canceled',
        'registration-questions-pending'
    );

    -- Never complete the purchase without a confirmed attendee row
    if not found then
        raise exception 'attendee cannot be confirmed for this event';
    end if;

    -- Persist the completed external purchase and organizer payment details
    update event_purchase
    set
        completed_at = current_timestamp,
        external_payment_details = v_details,
        external_payment_marked_by_user_id = p_actor_user_id,
        hold_expires_at = null,
        status = 'completed',
        updated_at = current_timestamp
    where event_purchase_id = p_event_purchase_id;

    -- Record the organizer action after the state transition succeeds
    perform insert_audit_log(
        'event_purchase_external_payment_completed',
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

    -- Enqueue the welcome notification in the same transaction as completion
    if p_notification_template_data is not null then
        perform enqueue_notification(
            'event-welcome',
            p_notification_template_data,
            coalesce(p_notification_attachments, '[]'::jsonb),
            array[v_user_id]
        );
    end if;

    -- Return the identifiers needed by the caller after completion
    return jsonb_build_object(
        'community_id', v_community_id,
        'event_id', v_event_id,
        'transitioned', true,
        'user_id', v_user_id
    );
end;
$$ language plpgsql;
