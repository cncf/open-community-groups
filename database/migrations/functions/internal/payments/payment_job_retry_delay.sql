-- Returns the bounded exponential backoff applied after a payment job attempt.
create or replace function payment_job_retry_delay(p_attempt_count int)
returns interval as $$
    select make_interval(
        mins => least(30, power(2, greatest(p_attempt_count - 1, 0)))::int
    );
$$ language sql immutable;
