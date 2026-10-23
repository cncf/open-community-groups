-- Cancels an attendee's active pending checkout purchase.
create or replace function cancel_event_checkout(
    p_community_id uuid,
    p_event_id uuid,
    p_user_id uuid,
    p_configured_provider text default null
)
returns void as $$
declare
    v_event_id uuid;
    v_event_purchase_id uuid;
    v_event_ticket_type_id uuid;
begin
    -- Resolve the active checkout before taking lifecycle locks
    select
        ep.event_id,
        ep.event_purchase_id,
        ep.event_ticket_type_id
    into
        v_event_id,
        v_event_purchase_id,
        v_event_ticket_type_id
    from event_purchase ep
    join event e using (event_id)
    join "group" g using (group_id)
    where g.community_id = p_community_id
    and ep.event_id = p_event_id
    and ep.user_id = p_user_id
    and ep.status = 'pending'
    and ep.hold_expires_at > current_timestamp;

    -- Ignore requests without an active checkout in the community
    if not found then
        return;
    end if;

    -- Reconcile under the global event, tier, user, and purchase lock order
    perform reconcile_event_enrollment(
        v_event_id,
        v_event_ticket_type_id,
        p_configured_provider
    );

    -- Expire the attendee's active pending purchase, stopping when it is no longer pending
    if not expire_event_checkout_hold(v_event_purchase_id) then
        return;
    end if;

    -- Return linked offers to pending and fill the released capacity
    perform reconcile_event_enrollment(
        v_event_id,
        v_event_ticket_type_id,
        p_configured_provider
    );
end;
$$ language plpgsql;
