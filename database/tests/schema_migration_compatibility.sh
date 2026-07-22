#!/bin/sh
set -eu

config=$1
legacy_ref=${LEGACY_SCHEMA_MIGRATION_REF:-f2d3fd0d}
repo_root=$(git rev-parse --show-toplevel)
workspace=$(mktemp -d)

cleanup() {
    rm -rf "$workspace"
}
trap cleanup EXIT

git -C "$repo_root" archive "$legacy_ref" database/migrations/schema |
    tar -x -C "$workspace"

legacy_schema_dir="$workspace/database/migrations/schema"
rm -f "$legacy_schema_dir/0061_add_notification_delivery_retry.sql"

# Recreate the schema that was deployed before migration history was
# renumbered, then advance its recorded version to the production value.
(
    cd "$legacy_schema_dir"
    tern migrate --config "$config" --version-table version_schema --destination 47
)

psql "$(awk '
    /^\[database\]/ { next }
    /^host[[:space:]]*=/ { host=$3 }
    /^port[[:space:]]*=/ { port=$3 }
    /^database[[:space:]]*=/ { database=$3 }
    /^user[[:space:]]*=/ { user=$3 }
    /^password[[:space:]]*=/ { password=$3 }
    END { printf "postgresql://%s:%s@%s:%s/%s", user, password, host, port, database }
' "$config")" \
    --set ON_ERROR_STOP=1 \
    --command 'update version_schema set version = 48 where version = 47;'

(
    cd "$repo_root/database/migrations/schema"
    tern migrate --config "$config" --version-table version_schema
    tern status --config "$config" --version-table version_schema
)
