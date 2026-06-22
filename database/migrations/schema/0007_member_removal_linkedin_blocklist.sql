create table linkedin_blocklist (
    linkedin_subject text primary key,
    blocked_user_id uuid references "user" (user_id) on delete set null,
    blocked_by_user_id uuid references "user" (user_id) on delete set null,
    reason text,
    created_at timestamp with time zone default current_timestamp not null,
    constraint linkedin_blocklist_subject_check check (btrim(linkedin_subject) <> ''),
    constraint linkedin_blocklist_reason_check check (reason is null or btrim(reason) <> '')
);
