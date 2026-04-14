-- Used by the checkout-completed webhook flow after the provider refund
-- succeeds: converts an expired unfulfillable purchase into a refunded
-- purchase and records the automatic refund in the audit log
create or replace function record_automatic_refund_for_event_purchase(
    p_event_purchase_id uuid,
    p_provider_refund_id text
)
returns void as $$
declare
    v_community_id uuid;
    v_event_id uuid;
    v_group_id uuid;
    v_user_id uuid;
begin
    -- Lock the expired purchase before marking it as refunded
    select
        g.community_id,
        ep.event_id,
        g.group_id,
        ep.user_id
    into
        v_community_id,
        v_event_id,
        v_group_id,
        v_user_id
    from event_purchase ep
    join event e on e.event_id = ep.event_id
    join "group" g on g.group_id = e.group_id
    where ep.event_purchase_id = p_event_purchase_id
    and ep.status = 'expired'
    for update of ep;

    if not found then
        raise exception 'expired purchase not found';
    end if;

    -- Persist the refunded purchase state after the provider refund succeeds
    update event_purchase
    set
        refunded_at = current_timestamp,
        status = 'refunded',
        updated_at = current_timestamp
    where event_purchase_id = p_event_purchase_id;

    -- Record the automatic refund for later reconciliation and support work
    perform insert_audit_log(
        'event_refunded',
        null,
        'event',
        v_event_id,
        v_community_id,
        v_group_id,
        v_event_id,
        jsonb_build_object(
            'automatic', true,
            'event_purchase_id', p_event_purchase_id,
            'provider_refund_id', p_provider_refund_id,
            'user_id', v_user_id
        )
    );
end;
$$ language plpgsql;
