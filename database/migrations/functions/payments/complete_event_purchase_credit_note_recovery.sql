-- Completes a credit note issued outside OCG.
create or replace function complete_event_purchase_credit_note_recovery(
    p_actor_user_id uuid,
    p_group_id uuid,
    p_credit_note_id uuid,
    p_provider_credit_note_id text,
    p_recovery_reference text,
    p_recovery_note text
)
returns void as $$
declare
    v_credit_note record;
begin
    -- Validate the operator and required recovery evidence
    if p_actor_user_id is null then
        raise exception 'actor user id is required';
    end if;

    if p_group_id is null then
        raise exception 'group id is required';
    end if;

    if nullif(btrim(p_provider_credit_note_id), '') is null then
        raise exception 'provider credit-note id is required';
    end if;

    if nullif(btrim(p_recovery_reference), '') is null then
        raise exception 'recovery reference is required';
    end if;

    if nullif(btrim(p_recovery_note), '') is null then
        raise exception 'recovery note is required';
    end if;

    -- Lock the exhausted work item and resolve its authorization scope
    select
        epcn.*,
        g.community_id,
        e.event_id,
        ep.event_purchase_id
    into v_credit_note
    from event_purchase_credit_note epcn
    join event_purchase_refund epr using (event_purchase_refund_id)
    join event_purchase ep using (event_purchase_id)
    join event e using (event_id)
    join "group" g using (group_id)
    where epcn.event_purchase_credit_note_id = p_credit_note_id
    and e.group_id = p_group_id
    for update of epcn;

    if not found then
        raise exception 'recoverable credit note not found';
    end if;

    if not user_has_group_permission(
        v_credit_note.community_id,
        p_group_id,
        p_actor_user_id,
        'group.events.write'
    ) then
        raise exception 'events write access is required';
    end if;

    -- Treat an exact repeated completion as an idempotent operator retry
    if v_credit_note.recovery_completed_at is not null then
        if v_credit_note.recovery_completed_by_user_id <> p_actor_user_id
           or v_credit_note.provider_credit_note_id <> btrim(p_provider_credit_note_id)
           or v_credit_note.recovery_note <> btrim(p_recovery_note)
           or v_credit_note.recovery_reference <> btrim(p_recovery_reference) then
            raise exception 'credit-note recovery already completed with different evidence';
        end if;

        return;
    end if;

    if v_credit_note.status <> 'failed' or v_credit_note.attempt_count < 10 then
        raise exception 'recoverable credit note not found';
    end if;

    -- Persist the issued provider document and recovery evidence
    update event_purchase_credit_note
    set
        completed_at = current_timestamp,
        failure_message = null,
        provider_credit_note_id = btrim(p_provider_credit_note_id),
        recovery_completed_at = current_timestamp,
        recovery_completed_by_user_id = p_actor_user_id,
        recovery_note = btrim(p_recovery_note),
        recovery_reference = btrim(p_recovery_reference),
        status = 'issued',
        updated_at = current_timestamp
    where event_purchase_credit_note_id = p_credit_note_id;

    -- Record the operator completion in the event audit trail
    perform insert_audit_log(
        'event_credit_note_recovery_completed',
        p_actor_user_id,
        'event',
        v_credit_note.event_id,
        v_credit_note.community_id,
        p_group_id,
        v_credit_note.event_id,
        jsonb_build_object(
            'event_purchase_credit_note_id', p_credit_note_id,
            'event_purchase_id', v_credit_note.event_purchase_id,
            'provider_credit_note_id', btrim(p_provider_credit_note_id),
            'recovery_note', btrim(p_recovery_note),
            'recovery_reference', btrim(p_recovery_reference)
        )
    );
end;
$$ language plpgsql;
