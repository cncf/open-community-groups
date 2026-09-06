-- Completes an exhausted payment job with the operator evidence that resolved it outside OCG.
create or replace function record_payment_job_recovery(
    p_payment_job_id uuid,
    p_actor_user_id uuid,
    p_recovery_reference text,
    p_recovery_note text
)
returns void as $$
begin
    -- Complete the unclaimed job and attach the external evidence
    update payment_job
    set
        claim_id = null,
        claimed_at = null,
        completed_at = current_timestamp,
        failure_message = null,
        recovery_completed_at = current_timestamp,
        recovery_completed_by_user_id = p_actor_user_id,
        recovery_note = btrim(p_recovery_note),
        recovery_reference = btrim(p_recovery_reference),
        status = 'completed',
        updated_at = current_timestamp
    where payment_job_id = p_payment_job_id
    and status <> 'completed'
    and claim_id is null;

    -- Reject jobs that are missing, already completed, or held by a worker
    if not found then
        raise exception 'payment job is not recoverable';
    end if;
end;
$$ language plpgsql;
