-- Adds external provider details to users.

alter table "user" add column provider jsonb;
