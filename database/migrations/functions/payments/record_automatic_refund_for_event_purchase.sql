-- Finalizes a recorded automatic refund after the provider succeeds.
create or replace function record_automatic_refund_for_event_purchase(
    p_event_purchase_id uuid,
    p_provider_refund_id text
)
returns void as $$
declare
    v_community_id uuid;
    v_event_id uuid;
    v_event_purchase_refund_id uuid;
    v_group_id uuid;
    v_user_id uuid;
begin
    -- Treat already finalized automatic refunds as successful retries
    select
        g.community_id,
        ep.event_id,
        epr.event_purchase_refund_id,
        g.group_id,
        ep.user_id
    into
        v_community_id,
        v_event_id,
        v_event_purchase_refund_id,
        v_group_id,
        v_user_id
    from event_purchase ep
    join event e on e.event_id = ep.event_id
    join "group" g on g.group_id = e.group_id
    join event_purchase_refund epr on epr.event_purchase_id = ep.event_purchase_id
    where ep.event_purchase_id = p_event_purchase_id
    and ep.status = 'refunded'
    and epr.kind = 'automatic-unfulfillable-checkout'
    and epr.provider_refund_id = p_provider_refund_id
    and epr.status = 'finalized'
    for update of ep, epr;

    if found then
        return;
    end if;

    -- Lock the refund-pending purchase before marking it as refunded
    select
        g.community_id,
        ep.event_id,
        epr.event_purchase_refund_id,
        g.group_id,
        ep.user_id
    into
        v_community_id,
        v_event_id,
        v_event_purchase_refund_id,
        v_group_id,
        v_user_id
    from event_purchase ep
    join event e on e.event_id = ep.event_id
    join "group" g on g.group_id = e.group_id
    join event_purchase_refund epr on epr.event_purchase_id = ep.event_purchase_id
    where ep.event_purchase_id = p_event_purchase_id
    and ep.status = 'refund-pending'
    and epr.kind = 'automatic-unfulfillable-checkout'
    and epr.provider_refund_id = p_provider_refund_id
    and epr.status = 'provider-succeeded'
    for update of ep, epr;

    if not found then
        raise exception 'refund-pending purchase not found';
    end if;

    -- Persist the refunded purchase state after the provider refund succeeds
    update event_purchase
    set
        refunded_at = current_timestamp,
        status = 'refunded',
        updated_at = current_timestamp
    where event_purchase_id = p_event_purchase_id;

    -- Mark the durable provider refund as locally finalized
    update event_purchase_refund
    set
        finalized_at = current_timestamp,
        status = 'finalized',
        updated_at = current_timestamp
    where event_purchase_refund_id = v_event_purchase_refund_id
    and status = 'provider-succeeded';

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
