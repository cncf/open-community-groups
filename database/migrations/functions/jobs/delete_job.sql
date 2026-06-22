create or replace function delete_job(p_user_id uuid, p_job_id uuid)
returns void language plpgsql as $$
begin
    delete from jobs_job
    where job_id = p_job_id
    and posted_by_user_id = p_user_id;

    if not found then
        raise exception 'job not found';
    end if;
end;
$$;
