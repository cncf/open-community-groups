-- Validates an event for checkout and returns its configured currency.
create or replace function prepare_event_checkout_validate_event(
    p_community_id uuid,
    p_event_id uuid
)
returns text as $$
declare
    v_currency_code text;
    v_event_canceled boolean;
    v_event_deleted boolean;
    v_event_ends_at timestamptz;
    v_event_published boolean;
    v_event_starts_at timestamptz;
    v_group_active boolean;
begin
    -- Lock the event and load the state required to start checkout
    select
        e.canceled,
        e.deleted,
        e.ends_at,
        g.active,
        e.payment_currency_code,
        e.published,
        e.starts_at
    into
        v_event_canceled,
        v_event_deleted,
        v_event_ends_at,
        v_group_active,
        v_currency_code,
        v_event_published,
        v_event_starts_at
    from event e
    join "group" g on g.group_id = e.group_id
    where e.event_id = p_event_id
    and g.community_id = p_community_id
    for update of e;

    -- Reject events whose current state no longer allows starting checkout
    if not found
       or not v_group_active
       or v_event_deleted
       or not v_event_published
       or v_event_canceled
       or (
           coalesce(v_event_ends_at, v_event_starts_at) is not null
           and coalesce(v_event_ends_at, v_event_starts_at) <= current_timestamp
       ) then
        raise exception 'event not found or inactive';
    end if;

    -- Return the optional event currency after state validation
    return v_currency_code;
end;
$$ language plpgsql;
