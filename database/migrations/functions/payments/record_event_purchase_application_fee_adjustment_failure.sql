-- Releases an application-fee adjustment claim for bounded automatic retries.
create or replace function record_event_purchase_application_fee_adjustment_failure(
    p_adjustment_id uuid,
    p_claim_id uuid,
    p_failure_message text
)
returns void as $$
begin
    update event_purchase_application_fee_adjustment
    set
        claim_id = null,
        claimed_at = null,
        failure_message = nullif(btrim(p_failure_message), ''),
        next_attempt_at = current_timestamp
            + least(power(2, attempt_count)::int, 60) * interval '1 minute',
        status = 'failed',
        updated_at = current_timestamp
    where event_purchase_application_fee_adjustment_id = p_adjustment_id
    and claim_id = p_claim_id
    and status = 'processing';

    if not found then
        raise exception 'application-fee adjustment claim is stale';
    end if;
end;
$$ language plpgsql;
