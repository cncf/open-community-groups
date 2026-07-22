create table if not exists group_accelerator_program (
    group_accelerator_program_id uuid primary key default gen_random_uuid(),
    group_id uuid not null references "group" (group_id) on delete cascade,
    created_by uuid not null references "user" (user_id),
    name text not null,
    summary text not null,
    description text,
    application_url text,
    curriculum_url text,
    active boolean default true not null,
    created_at timestamptz default current_timestamp not null,
    updated_at timestamptz,
    constraint group_accelerator_program_name_check check (btrim(name) <> ''),
    constraint group_accelerator_program_summary_check check (btrim(summary) <> ''),
    constraint group_accelerator_program_description_check check (description is null or btrim(description) <> ''),
    constraint group_accelerator_program_application_url_check check (application_url is null or btrim(application_url) <> ''),
    constraint group_accelerator_program_curriculum_url_check check (curriculum_url is null or btrim(curriculum_url) <> '')
);

create index if not exists group_accelerator_program_group_id_idx
on group_accelerator_program (group_id, active desc, created_at desc);

create table if not exists group_accelerator_cohort (
    group_accelerator_cohort_id uuid primary key default gen_random_uuid(),
    group_accelerator_program_id uuid not null references group_accelerator_program (group_accelerator_program_id) on delete cascade,
    created_by uuid not null references "user" (user_id),
    name text not null,
    status text default 'planned' not null check (status in ('planned', 'open', 'running', 'completed', 'archived')),
    starts_on date,
    ends_on date,
    application_deadline date,
    capacity integer,
    created_at timestamptz default current_timestamp not null,
    updated_at timestamptz,
    constraint group_accelerator_cohort_name_check check (btrim(name) <> ''),
    constraint group_accelerator_cohort_capacity_check check (capacity is null or capacity > 0),
    constraint group_accelerator_cohort_dates_check check (starts_on is null or ends_on is null or starts_on <= ends_on)
);

create index if not exists group_accelerator_cohort_program_id_idx
on group_accelerator_cohort (group_accelerator_program_id, status, starts_on desc nulls last);

create table if not exists group_accelerator_application (
    group_accelerator_application_id uuid primary key default gen_random_uuid(),
    group_accelerator_cohort_id uuid not null references group_accelerator_cohort (group_accelerator_cohort_id) on delete cascade,
    user_id uuid references "user" (user_id) on delete set null,
    applicant_name text not null,
    applicant_email text not null,
    project_name text not null,
    project_url text,
    pitch text not null,
    goals text,
    status text default 'submitted' not null check (status in ('submitted', 'reviewing', 'accepted', 'rejected', 'waitlisted')),
    reviewer_notes text,
    reviewed_by uuid references "user" (user_id) on delete set null,
    reviewed_at timestamptz,
    created_at timestamptz default current_timestamp not null,
    updated_at timestamptz,
    constraint group_accelerator_application_applicant_name_check check (btrim(applicant_name) <> ''),
    constraint group_accelerator_application_applicant_email_check check (btrim(applicant_email) <> ''),
    constraint group_accelerator_application_project_name_check check (btrim(project_name) <> ''),
    constraint group_accelerator_application_project_url_check check (project_url is null or btrim(project_url) <> ''),
    constraint group_accelerator_application_pitch_check check (btrim(pitch) <> ''),
    constraint group_accelerator_application_goals_check check (goals is null or btrim(goals) <> '')
);

create index if not exists group_accelerator_application_cohort_id_idx
on group_accelerator_application (group_accelerator_cohort_id, status, created_at desc);

create table if not exists group_accelerator_member (
    group_accelerator_member_id uuid primary key default gen_random_uuid(),
    group_accelerator_cohort_id uuid not null references group_accelerator_cohort (group_accelerator_cohort_id) on delete cascade,
    group_accelerator_application_id uuid references group_accelerator_application (group_accelerator_application_id) on delete set null,
    user_id uuid references "user" (user_id) on delete set null,
    display_name text not null,
    project_name text not null,
    project_url text,
    status text default 'active' not null check (status in ('active', 'graduated', 'dropped')),
    created_at timestamptz default current_timestamp not null,
    updated_at timestamptz,
    constraint group_accelerator_member_display_name_check check (btrim(display_name) <> ''),
    constraint group_accelerator_member_project_name_check check (btrim(project_name) <> ''),
    constraint group_accelerator_member_project_url_check check (project_url is null or btrim(project_url) <> ''),
    unique (group_accelerator_cohort_id, group_accelerator_application_id)
);

create index if not exists group_accelerator_member_cohort_id_idx
on group_accelerator_member (group_accelerator_cohort_id, status, created_at desc);

create table if not exists group_accelerator_week (
    group_accelerator_week_id uuid primary key default gen_random_uuid(),
    group_accelerator_cohort_id uuid not null references group_accelerator_cohort (group_accelerator_cohort_id) on delete cascade,
    created_by uuid not null references "user" (user_id),
    week_number integer not null,
    title text not null,
    goals text,
    resources_url text,
    deliverable text,
    starts_on date,
    due_on date,
    created_at timestamptz default current_timestamp not null,
    updated_at timestamptz,
    constraint group_accelerator_week_number_check check (week_number > 0),
    constraint group_accelerator_week_title_check check (btrim(title) <> ''),
    constraint group_accelerator_week_goals_check check (goals is null or btrim(goals) <> ''),
    constraint group_accelerator_week_resources_url_check check (resources_url is null or btrim(resources_url) <> ''),
    constraint group_accelerator_week_deliverable_check check (deliverable is null or btrim(deliverable) <> ''),
    constraint group_accelerator_week_dates_check check (starts_on is null or due_on is null or starts_on <= due_on),
    unique (group_accelerator_cohort_id, week_number)
);

create index if not exists group_accelerator_week_cohort_id_idx
on group_accelerator_week (group_accelerator_cohort_id, week_number);

create table if not exists group_accelerator_weekly_update (
    group_accelerator_weekly_update_id uuid primary key default gen_random_uuid(),
    group_accelerator_member_id uuid not null references group_accelerator_member (group_accelerator_member_id) on delete cascade,
    group_accelerator_week_id uuid not null references group_accelerator_week (group_accelerator_week_id) on delete cascade,
    user_id uuid references "user" (user_id) on delete set null,
    shipped text not null,
    metrics text,
    blockers text,
    asks text,
    links text,
    status text default 'submitted' not null check (status in ('submitted', 'reviewed')),
    reviewer_notes text,
    reviewed_by uuid references "user" (user_id) on delete set null,
    reviewed_at timestamptz,
    created_at timestamptz default current_timestamp not null,
    updated_at timestamptz,
    constraint group_accelerator_weekly_update_shipped_check check (btrim(shipped) <> ''),
    unique (group_accelerator_member_id, group_accelerator_week_id)
);

create index if not exists group_accelerator_weekly_update_week_id_idx
on group_accelerator_weekly_update (group_accelerator_week_id, status, created_at desc);
