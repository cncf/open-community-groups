alter table "user"
add column if not exists coffee_meet_enabled boolean default true not null;
