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
    v_admission_offer admission_offer;
    v_event event;
    v_group "group";
    v_lock record;
    v_purchase event_purchase;
begin
    -- Require the group scope of the dashboard route, never deriving it
    if p_group_id is null then
        raise exception 'group id is required';
    end if;

    -- Lock the group, event and purchase, reconciling enrollment before the purchase lock
    select *
    into v_lock
    from lock_event_purchase_for_completion(p_event_purchase_id, p_group_id);
    v_admission_offer := v_lock.admission_offer_row;
    v_event := v_lock.event_row;
    v_group := v_lock.group_row;
    v_purchase := v_lock.purchase_row;

    -- Return early on idempotent replays of a completed external purchase
    if v_purchase.status = 'completed' and v_purchase.charge_model = 'external' then
        return jsonb_build_object(
            'community_id', v_group.community_id,
            'event_id', v_event.event_id,
            'transitioned', false,
            'user_id', v_purchase.user_id
        );
    end if;

    -- Reject purchases that are not an external pending hold
    if v_purchase.charge_model <> 'external' then
        raise exception 'only external purchases can be marked paid locally' using errcode = 'OCG01';
    end if;

    -- Reject purchases that left the pending state
    if v_purchase.status <> 'pending' then
        raise exception 'purchase is no longer pending' using errcode = 'OCG01';
    end if;

    -- Complete the reservation and confirm the attendee seat
    perform fulfill_event_purchase_seat(v_purchase, v_event, v_group, v_admission_offer);

    -- Persist the completed external purchase and organizer payment details
    update event_purchase
    set
        completed_at = current_timestamp,
        external_payment_details = nullif(btrim(p_details), ''),
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
        v_event.event_id,
        v_group.community_id,
        p_group_id,
        v_event.event_id,
        jsonb_build_object(
            'event_purchase_id', p_event_purchase_id,
            'user_id', v_purchase.user_id
        )
    );

    -- Enqueue the welcome notification in the same transaction as completion
    if p_notification_template_data is not null then
        perform enqueue_notification(
            'event-welcome',
            p_notification_template_data,
            coalesce(p_notification_attachments, '[]'::jsonb),
            array[v_purchase.user_id]
        );
    end if;

    -- Return the identifiers needed by the caller after completion
    return jsonb_build_object(
        'community_id', v_group.community_id,
        'event_id', v_event.event_id,
        'transitioned', true,
        'user_id', v_purchase.user_id
    );
end;
$$ language plpgsql;
