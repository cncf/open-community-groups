-- Loads authoritative event context required to complete a refund recovery.
create or replace function get_event_purchase_refund_recovery_context(
    p_group_id uuid,
    p_event_purchase_id uuid
)
returns jsonb as $$
declare
    v_context jsonb;
begin
    -- Load the group-scoped refund and notification context
    select jsonb_build_object(
        'community_id', g.community_id,
        'event_id', e.event_id,
        'event_purchase_refund_id', epr.event_purchase_refund_id,

        'notification_required', epr.finalized_at is null
    )
    into v_context
    from event_purchase_refund epr
    join event_purchase ep
        on ep.event_purchase_id = epr.event_purchase_id
    join event e on e.event_id = ep.event_id
    join "group" g on g.group_id = e.group_id
    where e.group_id = p_group_id
      and ep.event_purchase_id = p_event_purchase_id;

    -- Reject missing and cross-group purchases consistently
    if not found then
        raise exception 'event purchase refund not found';
    end if;

    -- Return the stable app-facing contract
    return v_context;
end;
$$ language plpgsql;
