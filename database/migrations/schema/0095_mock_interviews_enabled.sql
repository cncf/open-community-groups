alter table alliance
add column if not exists mock_interviews_enabled boolean default true not null;

alter table "group"
add column if not exists mock_interviews_enabled boolean default true not null;
