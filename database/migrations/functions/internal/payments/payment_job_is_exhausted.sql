-- Returns whether a payment job used every automatic attempt and now needs an operator.
create or replace function payment_job_is_exhausted(p_job payment_job)
returns boolean as $$
    select p_job.status in ('failed', 'pending')
    and p_job.attempt_count >= payment_job_max_attempts();
$$ language sql immutable;
