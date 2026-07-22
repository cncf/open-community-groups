alter table jobs_job
add column if not exists members_only boolean default false not null;

create index if not exists jobs_job_published_members_only_created_at_idx
on jobs_job (published, members_only, created_at desc);
