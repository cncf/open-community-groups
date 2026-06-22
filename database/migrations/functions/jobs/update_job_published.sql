create or replace function update_job_published(p_user_id uuid, p_job_id uuid, p_published boolean)
returns void language plpgsql as $$
begin
    update jobs_job
    set published = p_published,
        expires_at = case
            when p_published and expires_at <= current_timestamp
                then current_timestamp + interval '30 days'
            else expires_at
        end,
        updated_at = current_timestamp
    where job_id = p_job_id
    and posted_by_user_id = p_user_id;

    if not found then
        raise exception 'job not found';
    end if;
end;
$$;
