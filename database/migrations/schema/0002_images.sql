-- Stores uploaded images when using the database storage provider.
create table images (
    file_name text primary key,
    content_type text not null,
    created_at timestamptz default current_timestamp not null,
    created_by uuid not null references "user",
    data bytea not null
);
