-- Requeues an exhausted application-fee adjustment.
create or replace function requeue_event_purchase_application_fee_adjustment(
    p_group_id uuid,
    p_adjustment_id uuid
)
returns void as $$
begin
    -- Reset exhausted work for another bounded automatic attempt cycle
    update event_purchase_application_fee_adjustment epafa
    set
        attempt_count = 0,
        failure_message = null,
        next_attempt_at = current_timestamp,
        status = 'pending',
        updated_at = current_timestamp
    from event_purchase ep
    join event e using (event_id)
    where epafa.event_purchase_id = ep.event_purchase_id
    and e.group_id = p_group_id
    and epafa.event_purchase_application_fee_adjustment_id = p_adjustment_id
    and epafa.status = 'failed'
    and epafa.attempt_count >= 10;

    -- Reject missing, cross-group, or ineligible work
    if not found then
        raise exception 'retryable application-fee adjustment not found';
    end if;
end;
$$ language plpgsql;
