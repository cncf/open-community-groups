-- Restores a failed refund approval only before its durable provider handoff.
create or replace function revert_event_refund_approval(
    p_group_id uuid,
    p_event_id uuid,
    p_user_id uuid
)
returns void as $$
declare
    v_event_purchase_id uuid;
begin
    -- Lock the approval scope against concurrent durable refund handoffs
    select ep.event_purchase_id
    into v_event_purchase_id
    from event_purchase ep
    join event e on e.event_id = ep.event_id
    join event_refund_request err on err.event_purchase_id = ep.event_purchase_id
    where e.group_id = p_group_id
    and ep.event_id = p_event_id
    and ep.user_id = p_user_id
    and ep.status = 'refund-requested'
    and err.status = 'approving'
    for update of ep, err;

    if not found then
        return;
    end if;

    -- Preserve approving state after the durable refund handoff exists
    if exists (
        select 1
        from event_purchase_refund
        where event_purchase_id = v_event_purchase_id
    ) then
        return;
    end if;

    -- Restore the request only while it remains in the transient approval state
    update event_refund_request
    set
        status = 'pending',
        updated_at = current_timestamp
    where event_purchase_id = v_event_purchase_id
    and status = 'approving';
end;
$$ language plpgsql;
