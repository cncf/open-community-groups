create or replace function update_job_published(p_user_id uuid, p_job_id uuid, p_published boolean)
returns void language plpgsql as $$
begin
    update jobs_job
    set published = p_published,
        updated_at = current_timestamp
    where job_id = p_job_id
    and posted_by_user_id = p_user_id;

    if not found then
        raise exception 'job not found';
    end if;
end;
$$;
