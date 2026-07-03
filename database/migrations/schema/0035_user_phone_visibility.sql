alter table "user"
add column if not exists phone_country_code text,
add column if not exists phone_number text;

create table if not exists group_member_phone_request (
    group_member_phone_request_id uuid default gen_random_uuid() primary key,
    group_id uuid not null references "group" (group_id) on delete cascade,
    requester_user_id uuid not null references "user" (user_id) on delete cascade,
    recipient_user_id uuid not null references "user" (user_id) on delete cascade,
    status text default 'pending' not null check (status in ('pending', 'approved', 'rejected')),
    created_at timestamp with time zone default current_timestamp not null,
    updated_at timestamp with time zone default current_timestamp not null,
    check (requester_user_id <> recipient_user_id),
    unique (group_id, requester_user_id, recipient_user_id)
);

create index if not exists group_member_phone_request_recipient_status_idx
on group_member_phone_request (group_id, recipient_user_id, status, created_at desc);

create index if not exists group_member_phone_request_requester_status_idx
on group_member_phone_request (group_id, requester_user_id, status, created_at desc);
