-- Requeues an exhausted payment job after an administrator retries it.
create or replace function requeue_payment_job(
    p_group_id uuid,
    p_payment_job_id uuid
)
returns void as $$
begin
    -- Reset only exhausted work of the group whose domain row can still be processed
    update payment_job pj
    set
        attempt_count = 0,
        failure_message = null,
        next_attempt_at = current_timestamp,
        status = 'pending',
        updated_at = current_timestamp
    from event_purchase ep
    join event e on e.event_id = ep.event_id
    where pj.event_purchase_id = ep.event_purchase_id
    and e.group_id = p_group_id
    and pj.payment_job_id = p_payment_job_id
    and payment_job_is_exhausted(pj)
    and payment_job_is_ready(pj);

    -- Reject missing, cross-group, and ineligible work
    if not found then
        raise exception 'retryable payment job not found' using errcode = 'OCG01';
    end if;
end;
$$ language plpgsql;
