alter table "user"
add column if not exists mentorship_businesses boolean default false not null,
add column if not exists mentorship_individuals boolean default false not null,
add column if not exists mentorship_note text;

do $$
begin
    if not exists (
        select 1
        from pg_constraint
        where conname = 'user_mentorship_note_check'
    ) then
        alter table "user"
        add constraint user_mentorship_note_check
        check (btrim(mentorship_note) <> '');
    end if;
end;
$$;

create index if not exists user_mentorship_idx
on "user" (mentorship_individuals, mentorship_businesses)
where mentorship_individuals = true or mentorship_businesses = true;

create table if not exists mentorship_request (
    mentorship_request_id uuid default gen_random_uuid() primary key,
    mentor_user_id uuid not null references "user" (user_id) on delete cascade,
    requester_user_id uuid not null references "user" (user_id) on delete cascade,
    audience_type text not null check (audience_type in ('individual', 'business')),
    message text not null check (btrim(message) <> ''),
    created_at timestamp with time zone default current_timestamp not null
);

create index if not exists mentorship_request_mentor_user_id_created_at_idx
on mentorship_request (mentor_user_id, created_at desc);

create index if not exists mentorship_request_requester_user_id_created_at_idx
on mentorship_request (requester_user_id, created_at desc);
