-- Used by the attendee refund request flow on the event page: validates that
-- the purchase is still refundable, creates the pending refund request, marks
-- the purchase as refund-requested, and enqueues organizer notifications
create or replace function request_event_refund(
    p_community_id uuid,
    p_event_id uuid,
    p_user_id uuid,
    p_requested_reason text,
    p_notification_template_data jsonb
)
returns void as $$
declare
    v_event_purchase_id uuid;
    v_group_id uuid;
    v_purchase_status text;
    v_recipients uuid[];
begin
    -- Lock the paid purchase before validating refund-request creation
    select
        ep.event_purchase_id,
        g.group_id,
        ep.status
    into
        v_event_purchase_id,
        v_group_id,
        v_purchase_status
    from event_purchase ep
    join event e on e.event_id = ep.event_id
    join "group" g on g.group_id = e.group_id
    where ep.event_id = p_event_id
    and ep.user_id = p_user_id
    and g.community_id = p_community_id
    and ep.amount_minor > 0
    and e.deleted = false
    and e.canceled = false
    and e.published = true
    and (e.starts_at is null or e.starts_at > current_timestamp)
    for update of ep;

    if not found then
        raise exception 'purchase not found or not refundable';
    end if;

    -- Reject duplicate requests and purchases that are no longer refundable
    if exists (
        select 1
        from event_refund_request
        where event_purchase_id = v_event_purchase_id
    ) then
        raise exception 'refund request already exists for this purchase';
    end if;

    -- Only completed paid purchases can enter the refund-request flow
    if v_purchase_status <> 'completed' then
        raise exception 'purchase not found or not refundable';
    end if;

    -- Create the pending refund request owned by the attendee
    insert into event_refund_request (
        event_purchase_id,
        requested_by_user_id,
        requested_reason,
        status
    ) values (
        v_event_purchase_id,
        p_user_id,
        nullif(p_requested_reason, ''),
        'pending'
    );

    -- Move the purchase into the refund-requested state
    update event_purchase
    set
        status = 'refund-requested',
        updated_at = current_timestamp
    where event_purchase_id = v_event_purchase_id;

    -- Track the attendee refund request in the audit log
    perform insert_audit_log(
        'event_refund_requested',
        p_user_id,
        'event',
        p_event_id,
        p_community_id,
        v_group_id,
        p_event_id,
        jsonb_build_object(
            'event_purchase_id', v_event_purchase_id,
            'user_id', p_user_id
        )
    );

    -- Resolve recipients and enqueue the organizer notification transactionally
    select coalesce(array_agg(value::uuid order by value::uuid), '{}')
    into v_recipients
    from json_array_elements_text(list_group_team_members_ids(v_group_id));

    if coalesce(array_length(v_recipients, 1), 0) = 0 then
        raise exception 'refund request notification has no recipients';
    end if;

    -- Notify the accepted group team members who can review the request
    perform enqueue_notification(
        'event-refund-requested',
        p_notification_template_data,
        '[]'::jsonb,
        v_recipients
    );
end;
$$ language plpgsql;
