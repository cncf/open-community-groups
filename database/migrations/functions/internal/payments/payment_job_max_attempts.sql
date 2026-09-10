-- Returns the number of automatic attempts a payment job gets before operator action is required.
create or replace function payment_job_max_attempts()
returns int as $$
    select 10;
$$ language sql immutable;
