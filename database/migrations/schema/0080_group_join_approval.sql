alter table "group"
    add column if not exists membership_approval_required boolean default false not null;

create table if not exists group_join_request (
    group_id uuid not null references "group" (group_id) on delete cascade,
    user_id uuid not null references "user" (user_id) on delete cascade,
    status text default 'pending' not null,
    created_at timestamp with time zone default current_timestamp not null,
    reviewed_at timestamp with time zone,
    reviewed_by uuid references "user" (user_id) on delete set null,
    primary key (group_id, user_id),
    constraint group_join_request_status_chk check (status in ('pending', 'approved', 'rejected')),
    constraint group_join_request_review_chk check (
        (status = 'pending' and reviewed_at is null and reviewed_by is null)
        or (status <> 'pending' and reviewed_at is not null)
    )
);

create index if not exists group_join_request_group_status_created_at_idx
on group_join_request (group_id, status, created_at desc);
