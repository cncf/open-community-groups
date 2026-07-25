-- Deletes completed badge award job summaries after their retention period.
create or replace function cleanup_badge_award_jobs(
    p_retention_seconds bigint default 2592000
)
returns integer as $$
declare
    v_deleted_count integer;
begin
    -- Validate the operator-controlled retention boundary
    if p_retention_seconds <= 0 then
        raise exception 'badge award job retention must be positive';
    end if;

    -- Remove one bounded batch of successful summaries outside the retention window
    with expired_jobs as (
        select badge_award_job_id
        from badge_award_job
        where status = 'completed'
        and completed_at < current_timestamp - make_interval(secs => p_retention_seconds)
        order by completed_at, badge_award_job_id
        for update skip locked
        limit 100
    )
    delete from badge_award_job baj
    using expired_jobs expired
    where baj.badge_award_job_id = expired.badge_award_job_id;

    get diagnostics v_deleted_count = row_count;
    return v_deleted_count;
end;
$$ language plpgsql;
