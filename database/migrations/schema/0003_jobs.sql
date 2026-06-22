create table jobs_job (
    job_id uuid default gen_random_uuid() primary key,
    posted_by_user_id uuid not null references "user" (user_id) on delete cascade,
    title text not null,
    slug text not null unique,
    company_name text not null,
    summary text not null,
    description text not null,
    apply_url text not null,
    location text,
    remote boolean default false not null,
    tags text[] default '{}'::text[] not null,
    published boolean default true not null,
    created_at timestamp with time zone default current_timestamp not null,
    updated_at timestamp with time zone
);

create index jobs_job_published_created_at_idx
on jobs_job (published, created_at desc);

create index jobs_job_posted_by_user_id_created_at_idx
on jobs_job (posted_by_user_id, created_at desc);

create index jobs_job_tags_idx
on jobs_job using gin (tags);

create table jobs_application (
    job_application_id uuid default gen_random_uuid() primary key,
    job_id uuid not null references jobs_job (job_id) on delete cascade,
    applicant_user_id uuid not null references "user" (user_id) on delete cascade,
    note text,
    created_at timestamp with time zone default current_timestamp not null,
    unique (job_id, applicant_user_id)
);

create index jobs_application_applicant_user_id_created_at_idx
on jobs_application (applicant_user_id, created_at desc);
