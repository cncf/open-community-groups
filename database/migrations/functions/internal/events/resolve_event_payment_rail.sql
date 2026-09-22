-- Selects the payment rail of a resolved event payload from the group's
-- external-payments selection. Paid-capable events in a group that selected
-- the external rail use it, which moves tax to the organizer; every other event
-- drops leftover external fields. Rejects a submitted external URL when the
-- group has not selected the rail, and rejects paid external events while the
-- group is not ready to collect on it.
create or replace function resolve_event_payment_rail(
    p_resolved event,
    p_ticket_types jsonb,
    p_group_external_selected boolean,
    p_group_external_ready boolean
)
returns table (
    external_mode boolean,
    resolved event
) as $$
declare
    v_external_mode boolean;
    v_resolved event := p_resolved;
begin
    -- Reject an external URL while the group has not selected the external rail
    if v_resolved.external_payment_url is not null and not p_group_external_selected then
        raise exception 'external payments are not available for this event' using errcode = 'OCG01';
    end if;

    -- Use the external rail only for paid events while the group selects it
    v_external_mode := is_event_ticketing_payload_paid_capable(p_ticket_types)
        and p_group_external_selected;

    -- Reject paid external events while the group cannot collect on its rail
    if v_external_mode and not p_group_external_ready then
        raise exception 'external payments require the legal name of the organization collecting payments' using errcode = 'OCG01';
    end if;

    -- Normalize external paid events onto organizer-managed tax
    if v_external_mode then
        v_resolved.manual_tax_rate_ids := '{}'::text[];
        v_resolved.tax_behavior := 'inclusive';
        v_resolved.tax_calculation_mode := 'none';

    -- Clear leftover external fields when the event is not on that rail
    else
        v_resolved.external_payment_instructions := null;
        v_resolved.external_payment_url := null;
        v_resolved.external_payment_window_hours := null;
    end if;

    -- Return the rail and the adjusted payload
    return query select v_external_mode, v_resolved;
end;
$$ language plpgsql;
