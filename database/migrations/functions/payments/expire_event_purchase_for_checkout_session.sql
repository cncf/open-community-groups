-- Expires a pending purchase and releases its checkout reservations.
create or replace function expire_event_purchase_for_checkout_session(
    p_provider text,
    p_provider_object_account_id text,
    p_provider_session_id text
)
returns void as $$
declare
    v_event_id uuid;
    v_event_purchase_id uuid;
    v_event_ticket_type_id uuid;
begin
    -- Resolve the owning event before taking lifecycle locks
    select
        ep.event_id,
        ep.event_purchase_id,
        ep.event_ticket_type_id
    into
        v_event_id,
        v_event_purchase_id,
        v_event_ticket_type_id
    from event_purchase ep
    where ep.payment_provider_id = p_provider
    and ep.provider_object_account_id = p_provider_object_account_id
    and ep.provider_checkout_session_id = p_provider_session_id;

    -- Ignore sessions that match no purchase
    if not found then
        return;
    end if;

    -- Reconcile under the global event, tier, user, and purchase lock order
    perform reconcile_event_enrollment(
        v_event_id,
        v_event_ticket_type_id,
        p_provider
    );

    -- Expire the checkout session's pending purchase, stopping when it is no longer pending
    if not expire_event_checkout_hold(v_event_purchase_id) then
        return;
    end if;

    -- Return linked offers to pending and fill the released capacity
    perform reconcile_event_enrollment(
        v_event_id,
        v_event_ticket_type_id,
        p_provider
    );
end;
$$ language plpgsql;
