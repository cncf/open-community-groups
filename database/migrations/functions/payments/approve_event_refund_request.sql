-- Finalizes a recorded refund request approval after the provider succeeds.
create or replace function approve_event_refund_request(
    p_actor_user_id uuid,
    p_group_id uuid,
    p_event_id uuid,
    p_user_id uuid,
    p_provider_refund_id text,
    p_review_note text
)
returns jsonb as $$
declare
    v_community_id uuid;
    v_event_discount_code_id uuid;
    v_event_purchase_id uuid;
    v_event_purchase_refund_id uuid;
begin
    -- Treat already finalized provider refunds as successful retries
    select
        g.community_id,
        ep.event_discount_code_id,
        ep.event_purchase_id,
        epr.event_purchase_refund_id
    into
        v_community_id,
        v_event_discount_code_id,
        v_event_purchase_id,
        v_event_purchase_refund_id
    from event_purchase ep
    join event e on e.event_id = ep.event_id
    join "group" g on g.group_id = e.group_id
    join event_refund_request err on err.event_purchase_id = ep.event_purchase_id
    join event_purchase_refund epr on epr.event_purchase_id = ep.event_purchase_id
    where g.group_id = p_group_id
    and ep.event_id = p_event_id
    and ep.user_id = p_user_id
    and ep.status = 'refunded'
    and err.status = 'approved'
    and epr.kind = 'refund-request-approval'
    and epr.provider_refund_id = p_provider_refund_id
    and epr.status = 'finalized'
    for update of ep, err, epr;

    if found then
        return jsonb_build_object(
            'community_id', v_community_id,
            'event_id', p_event_id,
            'finalized_now', false,
            'user_id', p_user_id
        );
    end if;

    -- Lock the refund request, purchase, and provider refund before finalizing
    select
        g.community_id,
        ep.event_discount_code_id,
        ep.event_purchase_id,
        epr.event_purchase_refund_id
    into
        v_community_id,
        v_event_discount_code_id,
        v_event_purchase_id,
        v_event_purchase_refund_id
    from event_purchase ep
    join event e on e.event_id = ep.event_id
    join "group" g on g.group_id = e.group_id
    join event_refund_request err on err.event_purchase_id = ep.event_purchase_id
    join event_purchase_refund epr on epr.event_purchase_id = ep.event_purchase_id
    where g.group_id = p_group_id
    and ep.event_id = p_event_id
    and ep.user_id = p_user_id
    and ep.status = 'refund-requested'
    and err.status = 'approving'
    and epr.kind = 'refund-request-approval'
    and epr.provider_refund_id = p_provider_refund_id
    and epr.status = 'provider-succeeded'
    for update of ep, err, epr;

    if not found then
        raise exception 'refund request not found';
    end if;

    -- Remove the attendee so the refunded purchase no longer occupies a seat
    delete from event_attendee
    where event_id = p_event_id
    and user_id = p_user_id
    and status = 'confirmed';

    -- Mark the purchase itself as refunded
    update event_purchase
    set
        refunded_at = current_timestamp,
        status = 'refunded',
        updated_at = current_timestamp
    where event_purchase_id = v_event_purchase_id;

    -- Return any reserved discount inventory to the event pool
    if v_event_discount_code_id is not null then
        perform release_event_discount_code_availability(v_event_discount_code_id);
    end if;

    -- Persist the review outcome on the refund request
    update event_refund_request
    set
        review_note = nullif(p_review_note, ''),
        reviewed_at = current_timestamp,
        reviewed_by_user_id = p_actor_user_id,
        status = 'approved',
        updated_at = current_timestamp
    where event_purchase_id = v_event_purchase_id
    and status = 'approving';

    -- Mark the durable provider refund as locally finalized
    update event_purchase_refund
    set
        finalized_at = current_timestamp,
        status = 'finalized',
        updated_at = current_timestamp
    where event_purchase_refund_id = v_event_purchase_refund_id
    and status = 'provider-succeeded';

    -- Record the completed refund for payment reconciliation and support work
    perform insert_audit_log(
        'event_refunded',
        p_actor_user_id,
        'event',
        p_event_id,
        v_community_id,
        p_group_id,
        p_event_id,
        jsonb_build_object(
            'event_purchase_id', v_event_purchase_id,
            'provider_refund_id', p_provider_refund_id,
            'user_id', p_user_id
        )
    );

    -- Return the identifiers the caller uses for follow-up work
    return jsonb_build_object(
        'community_id', v_community_id,
        'event_id', p_event_id,
        'finalized_now', true,
        'user_id', p_user_id
    );
end;
$$ language plpgsql;
