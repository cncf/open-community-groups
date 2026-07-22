alter table alliance
add column if not exists intentional_dating_enabled boolean default false not null;

alter table "group"
add column if not exists intentional_dating_enabled boolean default false not null;

alter table "user"
add column if not exists intentional_dating_enabled boolean default false not null,
add column if not exists intentional_dating_goals text,
add column if not exists intentional_dating_preferences text;

create table if not exists intentional_dating_intro (
    intentional_dating_intro_id uuid primary key default gen_random_uuid(),
    alliance_id uuid not null references alliance(alliance_id),
    group_id uuid not null references "group"(group_id),
    introduced_by_user_id uuid not null references "user"(user_id),
    first_user_id uuid not null references "user"(user_id),
    second_user_id uuid not null references "user"(user_id),
    status text not null default 'introduced',
    admin_notes text,
    created_at timestamp with time zone not null default current_timestamp,
    updated_at timestamp with time zone not null default current_timestamp,
    constraint intentional_dating_intro_distinct_users check (first_user_id <> second_user_id),
    constraint intentional_dating_intro_status check (status in ('introduced', 'paused', 'closed'))
);

create index if not exists intentional_dating_intro_alliance_id_idx
on intentional_dating_intro(alliance_id);

create index if not exists intentional_dating_intro_group_id_idx
on intentional_dating_intro(group_id);

create index if not exists intentional_dating_intro_first_user_id_idx
on intentional_dating_intro(first_user_id);

create index if not exists intentional_dating_intro_second_user_id_idx
on intentional_dating_intro(second_user_id);
