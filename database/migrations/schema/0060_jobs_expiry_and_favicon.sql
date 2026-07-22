alter table jobs_job
add column if not exists expires_at timestamp with time zone;

update jobs_job
set expires_at = created_at + interval '30 days'
where expires_at is null;

alter table jobs_job
alter column expires_at set default current_timestamp + interval '30 days',
alter column expires_at set not null;

create index if not exists jobs_job_published_expires_at_created_at_idx
on jobs_job (published, expires_at, created_at desc);

update site
set favicon_url = '/static/images/favicon.png?v=20260622'
where title = 'GOUP Alliance';
