-- Removes the unused event registration requirement flag.

alter table event drop column if exists registration_required;
