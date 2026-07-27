-- Claims the next badge award job ready for one bounded processing attempt.
create or replace function claim_badge_award_job()
returns jsonb as $$
declare
    v_claim_id uuid := gen_random_uuid();
    v_job_id uuid;
begin
    -- Lock only the oldest due summary without loading its recipient rows
    select baj.badge_award_job_id
    into v_job_id
    from badge_award_job baj
    where baj.status = 'pending'
    and baj.next_attempt_at <= current_timestamp
    order by
        baj.next_attempt_at,
        baj.created_at,
        baj.badge_award_job_id
    for update skip locked
    limit 1;

    if not found then
        return null;
    end if;

    -- Persist ownership before returning work to the application
    update badge_award_job
    set
        claim_id = v_claim_id,
        claimed_at = current_timestamp,
        status = 'processing',
        updated_at = current_timestamp
    where badge_award_job_id = v_job_id;

    return jsonb_build_object(
        'badge_award_job_id', v_job_id,
        'claim_id', v_claim_id
    );
end;
$$ language plpgsql;
