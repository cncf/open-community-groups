-- Completes an exhausted credit note or application-fee adjustment resolved outside OCG.
create or replace function complete_payment_job_recovery(
    p_actor_user_id uuid,
    p_group_id uuid,
    p_payment_job_id uuid,
    p_provider_object_id text,
    p_recovery_reference text,
    p_recovery_note text
)
returns void as $$
declare
    v_adjustment event_purchase_application_fee_adjustment;
    v_audit_action text;
    v_audit_details jsonb;
    v_credit_note event_purchase_credit_note;
    v_job payment_job;
    v_locked record;
    v_provider_object_id text := btrim(p_provider_object_id);
    v_recorded_provider_object_id text;
begin
    -- Validate the operator and required recovery evidence
    if p_actor_user_id is null then
        raise exception 'actor user id is required';
    end if;

    -- Require the group scope of the dashboard route
    if p_group_id is null then
        raise exception 'group id is required';
    end if;

    -- Require the provider object created outside OCG
    if nullif(v_provider_object_id, '') is null then
        raise exception 'provider object id is required' using errcode = 'OCG01';
    end if;

    -- Require the external reference proving the operation
    if nullif(btrim(p_recovery_reference), '') is null then
        raise exception 'recovery reference is required' using errcode = 'OCG01';
    end if;

    -- Require the operator note explaining the recovery
    if nullif(btrim(p_recovery_note), '') is null then
        raise exception 'recovery note is required' using errcode = 'OCG01';
    end if;

    -- Resolve the job kind and audit scope within the group before taking locks
    select
        pj,
        g.community_id,
        e.event_id
    into v_locked
    from payment_job pj
    join event_purchase ep on ep.event_purchase_id = pj.event_purchase_id
    join event e on e.event_id = ep.event_id
    join "group" g on g.group_id = e.group_id
    where pj.payment_job_id = p_payment_job_id
    and e.group_id = p_group_id;

    -- Reject jobs outside the group
    if not found then
        raise exception 'recoverable payment job not found' using errcode = 'OCG01';
    end if;

    v_job := v_locked.pj;

    -- Lock the typed domain row before its job, in the order the worker outcome paths use
    case v_job.kind
        -- Fee adjustments record the provider application-fee refund
        when 'event-purchase-application-fee-adjustment' then
            select epafa.*
            into v_adjustment
            from event_purchase_application_fee_adjustment epafa
            where epafa.payment_job_id = v_job.payment_job_id
            for update;

            v_recorded_provider_object_id := v_adjustment.provider_application_fee_refund_id;

        -- Credit notes record the provider credit-note document
        when 'event-purchase-credit-note' then
            select epcn.*
            into v_credit_note
            from event_purchase_credit_note epcn
            where epcn.payment_job_id = v_job.payment_job_id
            for update;

            v_recorded_provider_object_id := v_credit_note.provider_credit_note_id;

        -- Refund recovery drives enrollment state and has its own entry point
        else
            raise exception 'payment job kind does not support provider object recovery';
    end case;

    -- Lock the job and reload the lifecycle state the recovery decides on
    select pj.*
    into v_job
    from payment_job pj
    where pj.payment_job_id = p_payment_job_id
    for update;

    -- Treat an exact repeated completion as an idempotent operator retry
    if v_job.recovery_completed_at is not null then
        -- Reject a repeated completion carrying different evidence
        if v_job.recovery_completed_by_user_id <> p_actor_user_id
           or v_recorded_provider_object_id <> v_provider_object_id
           or v_job.recovery_note <> btrim(p_recovery_note)
           or v_job.recovery_reference <> btrim(p_recovery_reference) then
            raise exception 'payment job recovery already completed with different evidence' using errcode = 'OCG01';
        end if;

        return;
    end if;

    -- Only exhausted automatic work is recoverable
    if not payment_job_is_exhausted(v_job) then
        raise exception 'recoverable payment job not found' using errcode = 'OCG01';
    end if;

    -- Write the typed outcome and the audit context of the job kind
    case v_job.kind
        -- Fee adjustments also unblock the reconciliation they gate
        when 'event-purchase-application-fee-adjustment' then
            perform apply_event_purchase_application_fee_adjustment_outcome(
                v_adjustment,
                v_provider_object_id
            );

            v_audit_action := 'event_application_fee_adjustment_recovery_completed';
            v_audit_details := jsonb_build_object(
                'event_purchase_application_fee_adjustment_id',
                    v_adjustment.event_purchase_application_fee_adjustment_id,
                'kind', v_adjustment.kind,
                'provider_application_fee_refund_id', v_provider_object_id
            );

        -- Credit notes issued outside OCG have no hosted document URLs
        when 'event-purchase-credit-note' then
            perform apply_event_purchase_credit_note_outcome(
                v_credit_note,
                v_provider_object_id,
                null,
                null
            );

            v_audit_action := 'event_credit_note_recovery_completed';
            v_audit_details := jsonb_build_object(
                'event_purchase_credit_note_id', v_credit_note.event_purchase_credit_note_id,
                'provider_credit_note_id', v_provider_object_id
            );
    end case;

    -- Complete the job with the external evidence
    perform record_payment_job_recovery(
        v_job.payment_job_id,
        p_actor_user_id,
        p_recovery_reference,
        p_recovery_note
    );

    -- Record the operator completion in the event audit trail
    perform insert_audit_log(
        v_audit_action,
        p_actor_user_id,
        'event',
        v_locked.event_id,
        v_locked.community_id,
        p_group_id,
        v_locked.event_id,
        v_audit_details || jsonb_build_object(
            'event_purchase_id', v_job.event_purchase_id,
            'payment_job_id', v_job.payment_job_id,
            'recovery_note', btrim(p_recovery_note),
            'recovery_reference', btrim(p_recovery_reference)
        )
    );
end;
$$ language plpgsql;
