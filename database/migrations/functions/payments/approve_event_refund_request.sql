-- Used by the dashboard refund approval flow after the provider refund succeeds:
-- marks the purchase as refunded, approves the refund request, releases any
-- reserved discount availability, and returns identifiers for notifications
create or replace function approve_event_refund_request(
    p_actor_user_id uuid,
    p_group_id uuid,
    p_event_id uuid,
    p_user_id uuid,
    p_provider_refund_id text,
    p_review_note text
)
returns jsonb as $$
declare
    v_community_id uuid;
    v_event_discount_code_id uuid;
    v_event_purchase_id uuid;
begin
    -- Lock the refund request and purchase before changing their state
    select
        g.community_id,
        ep.event_discount_code_id,
        ep.event_purchase_id
    into
        v_community_id,
        v_event_discount_code_id,
        v_event_purchase_id
    from event_purchase ep
    join event e on e.event_id = ep.event_id
    join "group" g on g.group_id = e.group_id
    join event_refund_request err on err.event_purchase_id = ep.event_purchase_id
    where g.group_id = p_group_id
    and ep.event_id = p_event_id
    and ep.user_id = p_user_id
    and ep.status = 'refund-requested'
    and err.status = 'approving'
    for update of ep, err;

    if not found then
        raise exception 'refund request not found';
    end if;

    -- Remove the attendee so the refunded purchase no longer occupies a seat
    delete from event_attendee
    where event_id = p_event_id
    and user_id = p_user_id;

    -- Mark the purchase itself as refunded
    update event_purchase
    set
        refunded_at = current_timestamp,
        status = 'refunded',
        updated_at = current_timestamp
    where event_purchase_id = v_event_purchase_id;

    -- Return any reserved discount inventory to the event pool
    if v_event_discount_code_id is not null then
        perform release_event_discount_code_availability(v_event_discount_code_id);
    end if;

    -- Persist the review outcome on the refund request
    update event_refund_request
    set
        review_note = nullif(p_review_note, ''),
        reviewed_at = current_timestamp,
        reviewed_by_user_id = p_actor_user_id,
        status = 'approved',
        updated_at = current_timestamp
    where event_purchase_id = v_event_purchase_id
    and status = 'approving';

    -- Record the completed refund for payment reconciliation and support work
    perform insert_audit_log(
        'event_refunded',
        p_actor_user_id,
        'event',
        p_event_id,
        v_community_id,
        p_group_id,
        p_event_id,
        jsonb_build_object(
            'event_purchase_id', v_event_purchase_id,
            'provider_refund_id', p_provider_refund_id,
            'user_id', p_user_id
        )
    );

    -- Return the identifiers the caller uses for follow-up work
    return jsonb_build_object(
        'community_id', v_community_id,
        'event_id', p_event_id,
        'user_id', p_user_id
    );
end;
$$ language plpgsql;
