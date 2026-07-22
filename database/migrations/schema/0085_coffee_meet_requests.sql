create table if not exists coffee_meet_request (
    coffee_meet_request_id uuid default gen_random_uuid() primary key,
    recipient_user_id uuid not null references "user" (user_id) on delete cascade,
    requester_user_id uuid not null references "user" (user_id) on delete cascade,
    message text not null check (btrim(message) <> ''),
    created_at timestamp with time zone default current_timestamp not null,
    check (recipient_user_id <> requester_user_id)
);

create index if not exists coffee_meet_request_recipient_user_id_created_at_idx
on coffee_meet_request (recipient_user_id, created_at desc);

create index if not exists coffee_meet_request_requester_user_id_created_at_idx
on coffee_meet_request (requester_user_id, created_at desc);
