alter table alliance
add column if not exists mentorship_enabled boolean default true not null;

alter table "group"
add column if not exists mentorship_enabled boolean default true not null;
