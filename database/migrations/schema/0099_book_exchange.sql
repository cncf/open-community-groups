alter table alliance
add column if not exists book_exchange_enabled boolean default false not null;

alter table "group"
add column if not exists book_exchange_enabled boolean default false not null;

alter table "user"
add column if not exists book_exchange_enabled boolean default false not null,
add column if not exists book_exchange_books text;
