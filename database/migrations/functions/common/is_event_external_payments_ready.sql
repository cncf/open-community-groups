-- Returns whether an event can create new external-payment holds.
create or replace function is_event_external_payments_ready(
    p_event_id uuid
)
returns boolean as $$
    select exists (
        select 1
        from event e
        where e.event_id = p_event_id
        and e.external_payment_url is not null
        and is_group_external_payments_ready(e.group_id)
    );
$$ language sql;
