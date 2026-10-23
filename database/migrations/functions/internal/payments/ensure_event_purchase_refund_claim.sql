-- Rejects a provider refund result when the locked refund row is missing or
-- the locked payment job is no longer claimed by the reporting worker.
create or replace function ensure_event_purchase_refund_claim(
    p_refund event_purchase_refund,
    p_job payment_job,
    p_expected_claim_id uuid
)
returns void as $$
begin
    -- Reject unknown refunds and refunds removed while waiting for the locks
    if p_refund.event_purchase_refund_id is null then
        raise exception 'event purchase refund not found';
    end if;

    -- Reject results from a worker that no longer owns the job
    if p_job.claim_id is distinct from p_expected_claim_id then
        raise exception 'event purchase refund claim is stale';
    end if;
end;
$$ language plpgsql;
