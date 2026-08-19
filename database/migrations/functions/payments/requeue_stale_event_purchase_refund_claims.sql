-- Requeues refund claims left processing by interrupted workers.
create or replace function requeue_stale_event_purchase_refund_claims()
returns int as $$
declare
    v_count int;
begin
    -- Release claims only after the worker processing timeout
    update event_purchase_refund
    set
        claim_id = null,
        claimed_at = null,
        failure_message = case
            -- Preserve provider diagnostics when the outcome remains unknown
            when provider_refunded_at is null then coalesce(
                failure_message,
                'refund worker claim expired'
            )
            -- Retain any context recorded alongside a provider success
            else failure_message
        end,
        next_attempt_at = current_timestamp,
        status = case
            -- Resume provider reconciliation after an abandoned unknown outcome
            when provider_refunded_at is null then 'provider-failed'
            -- Resume local finalization after a persisted provider success
            else 'provider-succeeded'
        end,
        terminal_failure = false,
        updated_at = current_timestamp
    where status = 'processing'
    and claimed_at < current_timestamp - interval '15 minutes';

    get diagnostics v_count = row_count;
    return v_count;
end;
$$ language plpgsql;
