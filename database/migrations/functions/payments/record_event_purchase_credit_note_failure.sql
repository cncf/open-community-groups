-- Releases a credit-note claim for bounded automatic retries.
create or replace function record_event_purchase_credit_note_failure(
    p_credit_note_id uuid,
    p_claim_id uuid,
    p_failure_message text
)
returns void as $$
begin
    update event_purchase_credit_note
    set
        claim_id = null,
        claimed_at = null,
        failure_message = nullif(btrim(p_failure_message), ''),
        next_attempt_at = current_timestamp
            + least(power(2, attempt_count)::int, 60) * interval '1 minute',
        status = 'failed',
        updated_at = current_timestamp
    where event_purchase_credit_note_id = p_credit_note_id
    and claim_id = p_claim_id
    and status = 'processing';

    if not found then
        raise exception 'credit-note claim is stale';
    end if;
end;
$$ language plpgsql;
