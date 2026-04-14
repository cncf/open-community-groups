-- Used by the dashboard refund approval flow when the provider refund call
-- fails: moves the refund request from approving back to pending so review
-- can be retried safely
create or replace function revert_event_refund_approval(
    p_group_id uuid,
    p_event_id uuid,
    p_user_id uuid
)
returns void as $$
    update event_refund_request err
    set
        status = 'pending',
        updated_at = current_timestamp
    from event_purchase ep
    join event e on e.event_id = ep.event_id
    where err.event_purchase_id = ep.event_purchase_id
    and e.group_id = p_group_id
    and ep.event_id = p_event_id
    and ep.user_id = p_user_id
    and ep.status = 'refund-requested'
    and err.status = 'approving';
$$ language sql;
