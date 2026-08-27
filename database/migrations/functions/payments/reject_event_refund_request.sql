-- Rejects a refund request and returns attendee notification data.
create or replace function reject_event_refund_request(
    p_actor_user_id uuid,
    p_group_id uuid,
    p_event_purchase_id uuid,
    p_review_note text
)
returns jsonb as $$
declare
    v_community_id uuid;
    v_event_id uuid;
    v_review_note text := nullif(btrim(p_review_note), '');
    v_user_id uuid;
begin
    -- Require an attendee-visible reason before locking mutable state
    if v_review_note is null then
        raise exception 'refund rejection reason is required';
    end if;

    -- Lock the event before its purchase and refund request
    perform 1
    from event e
    join event_purchase ep on ep.event_id = e.event_id
    where e.group_id = p_group_id
    and ep.event_purchase_id = p_event_purchase_id
    for update of e;

    -- Reject purchases outside the requested group
    if not found then
        raise exception 'refund request not found';
    end if;

    -- Lock and load the pending refund request before rejecting it
    select
        g.community_id,
        ep.event_id,
        ep.user_id
    into
        v_community_id,
        v_event_id,
        v_user_id
    from event_purchase ep
    join event e on e.event_id = ep.event_id
    join "group" g on g.group_id = e.group_id
    join event_refund_request err on err.event_purchase_id = ep.event_purchase_id
    where g.group_id = p_group_id
    and ep.event_purchase_id = p_event_purchase_id
    and ep.status = 'refund-requested'
    and err.status = 'pending'
    for update of ep, err;

    -- Reject refund requests that changed while waiting for their locks
    if not found then
        raise exception 'refund request not found';
    end if;

    -- Restore the purchase to its completed state
    update event_purchase
    set
        status = 'completed',
        updated_at = current_timestamp
    where event_purchase_id = p_event_purchase_id;

    -- Persist the rejection details on the refund request
    update event_refund_request
    set
        review_note = v_review_note,
        reviewed_at = current_timestamp,
        reviewed_by_user_id = p_actor_user_id,
        status = 'rejected',
        updated_at = current_timestamp
    where event_purchase_id = p_event_purchase_id
    and status = 'pending';

    -- Record the rejection for dashboard history and support review
    perform insert_audit_log(
        'event_refund_rejected',
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

    -- Return the identifiers the caller uses after the rejection step
    return jsonb_build_object(
        'community_id', v_community_id,
        'event_id', v_event_id,
        'user_id', v_user_id
    );
end;
$$ language plpgsql;
