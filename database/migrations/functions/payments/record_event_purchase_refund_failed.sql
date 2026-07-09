-- Records a failed provider refund attempt without overwriting success.
create or replace function record_event_purchase_refund_failed(
    p_event_purchase_refund_id uuid,
    p_failure_message text
)
returns void as $$
declare
    v_status text;
begin
    -- Lock the durable refund row before recording a retryable failure
    select status
    into v_status
    from event_purchase_refund
    where event_purchase_refund_id = p_event_purchase_refund_id
    for update;

    if not found then
        raise exception 'event purchase refund not found';
    end if;

    -- Preserve provider success and locally finalized refunds
    if v_status in ('provider-succeeded', 'finalized') then
        return;
    end if;

    -- Record the retryable provider failure
    update event_purchase_refund
    set
        failure_message = nullif(btrim(p_failure_message), ''),
        status = 'provider-failed',
        updated_at = current_timestamp
    where event_purchase_refund_id = p_event_purchase_refund_id;
end;
$$ language plpgsql;
