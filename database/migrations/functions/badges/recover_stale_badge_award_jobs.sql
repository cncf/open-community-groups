-- Requeues badge award jobs abandoned by interrupted workers.
create or replace function recover_stale_badge_award_jobs(
    p_processing_timeout_seconds bigint default 900,
    p_max_failures integer default 10
)
returns integer as $$
declare
    v_recovered_count integer;
begin
    -- Validate recovery controls before scanning active claims
    if p_max_failures <= 0 then
        raise exception 'badge award job failure limit must be positive';
    end if;
    if p_processing_timeout_seconds <= 0 then
        raise exception 'badge award job processing timeout must be positive';
    end if;

    -- Serialize recovery sweeps across application replicas
    if not pg_try_advisory_xact_lock(hashtextextended('ocg:badge-award-recovery', 0)) then
        return 0;
    end if;

    -- Release one bounded stale-claim batch or stop jobs that exhausted recovery
    with stale_jobs as (
        select badge_award_job_id
        from badge_award_job
        where status = 'processing'
        and claimed_at < current_timestamp - make_interval(secs => p_processing_timeout_seconds)
        order by claimed_at, badge_award_job_id
        for update skip locked
        limit 100
    )
    update badge_award_job baj
    set
        claim_id = null,
        claimed_at = null,
        completed_at = case
            when failure_count + 1 >= p_max_failures then current_timestamp
            else null
        end,
        error = 'badge award worker claim expired',
        failure_count = failure_count + 1,
        next_attempt_at = current_timestamp,
        status = case
            when failure_count + 1 >= p_max_failures then 'failed'
            else 'pending'
        end,
        updated_at = current_timestamp
    from stale_jobs stale
    where baj.badge_award_job_id = stale.badge_award_job_id;

    get diagnostics v_recovered_count = row_count;
    return v_recovered_count;
end;
$$ language plpgsql;
