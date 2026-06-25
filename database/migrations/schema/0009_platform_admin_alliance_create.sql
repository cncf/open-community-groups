alter table "user"
add column if not exists platform_admin boolean default false not null;
