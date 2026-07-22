alter table landscape_entry
drop constraint if exists landscape_entry_kind_check;

alter table landscape_entry
add constraint landscape_entry_kind_check
check (kind in ('startup', 'github_project', 'partner_community', 'podcast_lead', 'investor', 'accelerator'));

create table if not exists landscape_accelerator_profile (
    landscape_entry_id uuid primary key references landscape_entry (landscape_entry_id) on delete cascade,
    application_url text,
    curriculum_url text,
    cohort_status text check (cohort_status in ('planned', 'open', 'running', 'completed')),
    starts_on date,
    ends_on date,
    tracks text[] default '{}'::text[] not null,
    weekly_agenda jsonb,
    updated_at timestamp with time zone default current_timestamp not null,
    check (starts_on is null or ends_on is null or starts_on <= ends_on)
);
