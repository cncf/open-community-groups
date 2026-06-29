create table if not exists coffee_meet_subscription (
    group_id uuid not null references "group" (group_id) on delete cascade,
    user_id uuid not null references "user" (user_id) on delete cascade,
    frequency text not null check (frequency in ('weekly', 'biweekly', 'monthly')),
    active boolean default true not null,
    next_suggestion_at timestamp with time zone default current_timestamp not null,
    last_suggestion_at timestamp with time zone,
    created_at timestamp with time zone default current_timestamp not null,
    updated_at timestamp with time zone default current_timestamp not null,
    primary key (group_id, user_id)
);

create index if not exists coffee_meet_subscription_due_idx
on coffee_meet_subscription (next_suggestion_at, group_id)
where active = true;

create index if not exists coffee_meet_subscription_user_id_idx
on coffee_meet_subscription (user_id, active, next_suggestion_at);

create table if not exists coffee_meet_suggestion (
    coffee_meet_suggestion_id uuid default gen_random_uuid() primary key,
    group_id uuid not null references "group" (group_id) on delete cascade,
    subscriber_user_id uuid not null references "user" (user_id) on delete cascade,
    suggested_user_id uuid not null references "user" (user_id) on delete cascade,
    frequency text not null check (frequency in ('weekly', 'biweekly', 'monthly')),
    suggested_for timestamp with time zone default current_timestamp not null,
    notification_enqueued_at timestamp with time zone,
    created_at timestamp with time zone default current_timestamp not null,
    check (subscriber_user_id <> suggested_user_id)
);

create index if not exists coffee_meet_suggestion_subscriber_idx
on coffee_meet_suggestion (group_id, subscriber_user_id, created_at desc);

create index if not exists coffee_meet_suggestion_suggested_idx
on coffee_meet_suggestion (group_id, suggested_user_id, created_at desc);

insert into notification_kind (name, optional_notification)
values ('coffee-meet-suggestion', true)
on conflict (name) do update set optional_notification = excluded.optional_notification;
