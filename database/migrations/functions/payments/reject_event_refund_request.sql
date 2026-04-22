-- Used by the dashboard refund review flow when organizers reject a request:
-- restores the purchase to completed, marks the refund request as rejected,
-- and returns identifiers for attendee notification
create or replace function reject_event_refund_request(
    p_actor_user_id uuid,
    p_group_id uuid,
    p_event_id uuid,
    p_user_id uuid,
    p_review_note text
)
returns jsonb as $$
declare
    v_community_id uuid;
    v_event_purchase_id uuid;
begin
    -- Lock the pending refund request before rejecting it
    select
        g.community_id,
        ep.event_purchase_id
    into
        v_community_id,
        v_event_purchase_id
    from event_purchase ep
    join event e on e.event_id = ep.event_id
    join "group" g on g.group_id = e.group_id
    join event_refund_request err on err.event_purchase_id = ep.event_purchase_id
    where g.group_id = p_group_id
    and ep.event_id = p_event_id
    and ep.user_id = p_user_id
    and ep.status = 'refund-requested'
    and err.status = 'pending'
    for update of ep, err;

    if not found then
        raise exception 'refund request not found';
    end if;

    -- Restore the purchase to its completed state
    update event_purchase
    set
        status = 'completed',
        updated_at = current_timestamp
    where event_purchase_id = v_event_purchase_id;

    -- Persist the rejection details on the refund request
    update event_refund_request
    set
        review_note = nullif(p_review_note, ''),
        reviewed_at = current_timestamp,
        reviewed_by_user_id = p_actor_user_id,
        status = 'rejected',
        updated_at = current_timestamp
    where event_purchase_id = v_event_purchase_id
    and status = 'pending';

    -- Record the rejection for dashboard history and support review
    perform insert_audit_log(
        'event_refund_rejected',
        p_actor_user_id,
        'event',
        p_event_id,
        v_community_id,
        p_group_id,
        p_event_id,
        jsonb_build_object(
            'event_purchase_id', v_event_purchase_id,
            'user_id', p_user_id
        )
    );

    -- Return the identifiers the caller uses after the rejection step
    return jsonb_build_object(
        'community_id', v_community_id,
        'event_id', p_event_id,
        'user_id', p_user_id
    );
end;
$$ language plpgsql;
