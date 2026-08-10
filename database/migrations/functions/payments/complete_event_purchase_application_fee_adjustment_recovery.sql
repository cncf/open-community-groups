-- Completes an application-fee adjustment resolved outside OCG.
create or replace function complete_event_purchase_application_fee_adjustment_recovery(
    p_actor_user_id uuid,
    p_group_id uuid,
    p_adjustment_id uuid,
    p_provider_application_fee_refund_id text,
    p_recovery_reference text,
    p_recovery_note text
)
returns void as $$
declare
    v_adjustment record;
begin
    -- Validate the operator and required recovery evidence
    if p_actor_user_id is null then
        raise exception 'actor user id is required';
    end if;

    if p_group_id is null then
        raise exception 'group id is required';
    end if;

    if nullif(btrim(p_provider_application_fee_refund_id), '') is null then
        raise exception 'provider application-fee refund id is required';
    end if;

    if nullif(btrim(p_recovery_reference), '') is null then
        raise exception 'recovery reference is required';
    end if;

    if nullif(btrim(p_recovery_note), '') is null then
        raise exception 'recovery note is required';
    end if;

    -- Lock the exhausted work item and resolve its authorization scope
    select
        epafa.*,
        g.community_id,
        e.event_id
    into v_adjustment
    from event_purchase_application_fee_adjustment epafa
    join event_purchase ep using (event_purchase_id)
    join event e using (event_id)
    join "group" g using (group_id)
    where epafa.event_purchase_application_fee_adjustment_id = p_adjustment_id
    and e.group_id = p_group_id
    for update of epafa;

    if not found then
        raise exception 'recoverable application-fee adjustment not found';
    end if;

    if not user_has_group_permission(
        v_adjustment.community_id,
        p_group_id,
        p_actor_user_id,
        'group.events.write'
    ) then
        raise exception 'events write access is required';
    end if;

    -- Treat an exact repeated completion as an idempotent operator retry
    if v_adjustment.recovery_completed_at is not null then
        if v_adjustment.recovery_completed_by_user_id <> p_actor_user_id
           or v_adjustment.provider_application_fee_refund_id <>
                btrim(p_provider_application_fee_refund_id)
           or v_adjustment.recovery_note <> btrim(p_recovery_note)
           or v_adjustment.recovery_reference <> btrim(p_recovery_reference) then
            raise exception 'application-fee recovery already completed with different evidence';
        end if;

        return;
    end if;

    if v_adjustment.status <> 'failed' or v_adjustment.attempt_count < 10 then
        raise exception 'recoverable application-fee adjustment not found';
    end if;

    -- Persist the completed provider operation and recovery evidence
    update event_purchase_application_fee_adjustment
    set
        completed_at = current_timestamp,
        failure_message = null,
        provider_application_fee_refund_id =
            btrim(p_provider_application_fee_refund_id),
        recovery_completed_at = current_timestamp,
        recovery_completed_by_user_id = p_actor_user_id,
        recovery_note = btrim(p_recovery_note),
        recovery_reference = btrim(p_recovery_reference),
        status = 'completed',
        updated_at = current_timestamp
    where event_purchase_application_fee_adjustment_id = p_adjustment_id;

    -- Tax reconciliation remains gated on the application-fee correction
    if v_adjustment.kind = 'tax-reconciliation' then
        update event_purchase
        set
            financially_reconciled_at = coalesce(
                financially_reconciled_at,
                current_timestamp
            ),
            updated_at = current_timestamp
        where event_purchase_id = v_adjustment.event_purchase_id;
    end if;

    -- Record the operator completion in the event audit trail
    perform insert_audit_log(
        'event_application_fee_adjustment_recovery_completed',
        p_actor_user_id,
        'event',
        v_adjustment.event_id,
        v_adjustment.community_id,
        p_group_id,
        v_adjustment.event_id,
        jsonb_build_object(
            'event_purchase_application_fee_adjustment_id', p_adjustment_id,
            'event_purchase_id', v_adjustment.event_purchase_id,
            'kind', v_adjustment.kind,
            'provider_application_fee_refund_id',
                btrim(p_provider_application_fee_refund_id),
            'recovery_note', btrim(p_recovery_note),
            'recovery_reference', btrim(p_recovery_reference)
        )
    );
end;
$$ language plpgsql;
