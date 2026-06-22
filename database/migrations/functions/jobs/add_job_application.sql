create or replace function add_job_application(p_user_id uuid, p_job_id uuid, p_input jsonb)
returns void language plpgsql as $$
begin
    insert into jobs_application (job_id, applicant_user_id, note)
    select p_job_id, p_user_id, nullif(trim(p_input->>'note'), '')
    from jobs_job j
    where j.job_id = p_job_id
    and j.published = true
    and j.posted_by_user_id <> p_user_id
    on conflict (job_id, applicant_user_id) do update
    set note = excluded.note,
        created_at = current_timestamp;

    if not found then
        raise exception 'job not found';
    end if;
end;
$$;
