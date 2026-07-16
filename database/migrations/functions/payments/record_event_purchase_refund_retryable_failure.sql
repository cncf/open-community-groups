-- Releases a worker claim after a retryable provider communication failure.
create or replace function record_event_purchase_refund_retryable_failure(
    p_event_purchase_refund_id uuid,
    p_claim_id uuid,
    p_failure_message text
)
returns void as $$
begin
    -- Release only the current claim and schedule bounded exponential backoff
    update event_purchase_refund
    set
        claim_id = null,
        claimed_at = null,
        failure_message = coalesce(
            nullif(btrim(p_failure_message), ''),
            'provider refund attempt failed'
        ),
        next_attempt_at = current_timestamp + make_interval(
            mins => least(30, (power(2, greatest(attempt_count - 1, 0)))::int)
        ),
        status = 'provider-failed',
        terminal_failure = false,
        updated_at = current_timestamp
    where event_purchase_refund_id = p_event_purchase_refund_id
    and claim_id = p_claim_id
    and status = 'processing';

    if not found then
        raise exception 'event purchase refund claim is no longer current';
    end if;
end;
$$ language plpgsql;
