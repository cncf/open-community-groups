alter table alliance
add column if not exists report_public_enabled boolean default false not null;

alter table "group"
add column if not exists report_public_enabled boolean default false not null;
