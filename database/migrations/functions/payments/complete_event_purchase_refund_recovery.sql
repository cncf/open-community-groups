-- Completes an externally resolved terminal provider refund.
create or replace function complete_event_purchase_refund_recovery(
    p_actor_user_id uuid,
    p_event_purchase_refund_id uuid,
    p_recovery_reference text,
    p_recovery_note text
)
returns jsonb as $$
declare
    v_community_id uuid;
    v_event_discount_code_id uuid;
    v_event_id uuid;
    v_finalized_at timestamptz;
    v_group_id uuid;
    v_kind text;
    v_provider_refund_id text;
    v_purchase_id uuid;
    v_purchase_status text;
    v_recovery_completed_at timestamptz;
    v_recovery_completed_by_user_id uuid;
    v_recovery_note text;
    v_recovery_reference text;
    v_refund_status text;
    v_user_id uuid;
begin
    -- Validate the operator and required recovery evidence
    if p_actor_user_id is null then
        raise exception 'actor user id is required';
    end if;

    if nullif(btrim(p_recovery_reference), '') is null then
        raise exception 'recovery reference is required';
    end if;

    if nullif(btrim(p_recovery_note), '') is null then
        raise exception 'recovery note is required';
    end if;

    -- Resolve and lock the event before its purchase and durable refund
    select ep.event_id
    into v_event_id
    from event_purchase_refund epr
    join event_purchase ep on ep.event_purchase_id = epr.event_purchase_id
    where epr.event_purchase_refund_id = p_event_purchase_refund_id;

    if not found then
        raise exception 'event purchase refund not found';
    end if;

    perform 1
    from event
    where event_id = v_event_id
    for update;

    select
        g.community_id,
        ep.event_discount_code_id,
        e.group_id,
        epr.finalized_at,
        epr.kind,
        epr.provider_refund_id,
        ep.event_purchase_id,
        ep.status,
        epr.recovery_completed_at,
        epr.recovery_completed_by_user_id,
        epr.recovery_note,
        epr.recovery_reference,
        epr.status,
        ep.user_id
    into
        v_community_id,
        v_event_discount_code_id,
        v_group_id,
        v_finalized_at,
        v_kind,
        v_provider_refund_id,
        v_purchase_id,
        v_purchase_status,
        v_recovery_completed_at,
        v_recovery_completed_by_user_id,
        v_recovery_note,
        v_recovery_reference,
        v_refund_status,
        v_user_id
    from event_purchase_refund epr
    join event_purchase ep on ep.event_purchase_id = epr.event_purchase_id
    join event e on e.event_id = ep.event_id
    join "group" g on g.group_id = e.group_id
    where epr.event_purchase_refund_id = p_event_purchase_refund_id
    for update of ep, epr;

    if not found then
        raise exception 'recoverable event purchase refund not found';
    end if;

    -- Treat an exact repeated completion as an idempotent operator retry
    if v_recovery_completed_at is not null then
        if v_recovery_completed_by_user_id <> p_actor_user_id
           or v_recovery_note <> btrim(p_recovery_note)
           or v_recovery_reference <> btrim(p_recovery_reference) then
            raise exception 'refund recovery already completed with different evidence';
        end if;

        return jsonb_build_object(
            'event_id', v_event_id,
            'recovered_now', false,
            'user_id', v_user_id
        );
    end if;

    if v_refund_status <> 'provider-failed' or v_provider_refund_id is null then
        raise exception 'recoverable event purchase refund not found';
    end if;

    -- Validate the local lifecycle that the external recovery will complete
    if v_finalized_at is null then
        if v_kind = 'automatic-unfulfillable-checkout' then
            if v_purchase_status <> 'refund-pending' then
                raise exception 'recoverable event purchase refund not found';
            end if;
        elsif v_kind = 'refund-request-approval' then
            if v_purchase_status <> 'refund-requested' then
                raise exception 'recoverable event purchase refund not found';
            end if;

            perform 1
            from event_refund_request
            where event_purchase_id = v_purchase_id
            and status = 'approving'
            for update;

            if not found then
                raise exception 'recoverable event purchase refund not found';
            end if;
        else
            raise exception 'recoverable event purchase refund not found';
        end if;
    elsif v_purchase_status not in ('refund-recovery-pending', 'refunded') then
        raise exception 'recoverable event purchase refund not found';
    end if;

    -- Apply local finalization that did not happen before the terminal failure
    if v_finalized_at is null then
        if v_kind = 'refund-request-approval' then
            delete from event_attendee
            where event_id = v_event_id
            and user_id = v_user_id
            and status = 'confirmed';

            if v_event_discount_code_id is not null then
                perform release_event_discount_code_availability(v_event_discount_code_id);
            end if;

            update event_refund_request
            set
                review_note = btrim(p_recovery_note),
                reviewed_at = current_timestamp,
                reviewed_by_user_id = p_actor_user_id,
                status = 'approved',
                updated_at = current_timestamp
            where event_purchase_id = v_purchase_id
            and status = 'approving';
        end if;
    end if;

    -- Preserve the failed provider attempt and append the external recovery evidence
    update event_purchase_refund
    set
        finalized_at = coalesce(finalized_at, current_timestamp),
        recovery_completed_at = current_timestamp,
        recovery_completed_by_user_id = p_actor_user_id,
        recovery_note = btrim(p_recovery_note),
        recovery_reference = btrim(p_recovery_reference),
        updated_at = current_timestamp
    where event_purchase_refund_id = p_event_purchase_refund_id;

    update event_purchase
    set
        refunded_at = coalesce(refunded_at, current_timestamp),
        status = 'refunded',
        updated_at = current_timestamp
    where event_purchase_id = v_purchase_id;

    -- Record the immutable operator action with the external evidence
    perform insert_audit_log(
        'event_refund_recovery_completed',
        p_actor_user_id,
        'event',
        v_event_id,
        v_community_id,
        v_group_id,
        v_event_id,
        jsonb_build_object(
            'event_purchase_id', v_purchase_id,
            'event_purchase_refund_id', p_event_purchase_refund_id,
            'provider_refund_id', v_provider_refund_id,
            'recovery_note', btrim(p_recovery_note),
            'recovery_reference', btrim(p_recovery_reference),
            'user_id', v_user_id
        )
    );

    return jsonb_build_object(
        'event_id', v_event_id,
        'recovered_now', true,
        'user_id', v_user_id
    );
end;
$$ language plpgsql;
