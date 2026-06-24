create table if not exists group_member_spotlight (
    group_member_spotlight_id uuid primary key default uuid_generate_v4(),
    group_id uuid not null references "group" (group_id) on delete cascade,
    user_id uuid not null references "user" (user_id) on delete cascade,
    created_by uuid not null references "user" (user_id),
    title text not null,
    story text not null,
    image_url text,
    link_url text,
    featured boolean default false not null,
    published boolean default true not null,
    created_at timestamptz default current_timestamp not null,
    updated_at timestamptz,
    constraint group_member_spotlight_title_check check (btrim(title) <> ''),
    constraint group_member_spotlight_story_check check (btrim(story) <> ''),
    constraint group_member_spotlight_user_once_per_group unique (group_id, user_id)
);

create index if not exists group_member_spotlight_group_id_idx
on group_member_spotlight (group_id, featured desc, created_at desc);
