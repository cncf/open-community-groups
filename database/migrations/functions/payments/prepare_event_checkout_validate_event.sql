-- Used by prepare_event_checkout_purchase to validate event state and return currency
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
    v_payment_recipient jsonb;
begin
    -- Lock the event and validate that checkout is still allowed
    select
        e.canceled,
        e.deleted,
        e.ends_at,
        g.active,
        g.payment_recipient,
        e.payment_currency_code,
        e.published,
        e.starts_at
    into
        v_event_canceled,
        v_event_deleted,
        v_event_ends_at,
        v_group_active,
        v_payment_recipient,
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

    -- Require any payment recipient before validating provider-specific settings
    if v_payment_recipient is null then
        raise exception 'group payments recipient is not configured';
    end if;

    -- Require a configured Stripe recipient and a payment currency
    if coalesce(v_payment_recipient->>'provider', '') <> 'stripe' then
        raise exception 'group payments recipient is not configured for Stripe';
    end if;

    -- Require a payment currency to price the checkout session
    if v_currency_code is null then
        raise exception 'ticketed event is missing payment_currency_code';
    end if;

    -- Return the event currency used to price the checkout session
    return v_currency_code;
end;
$$ language plpgsql;
