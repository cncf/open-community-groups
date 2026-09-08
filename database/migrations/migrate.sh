#!/bin/sh

schemaVersionTable=version_schema
functionsVersionTable=version_functions

# Nested functions directories (functions/internal/<concern>/) require tern
# 2.3.0+, which discovers shared templates recursively. Older releases only
# scan one directory level and fail with "template ... not defined".
minTernVersion="2.3.0"

if ! command -v tern >/dev/null 2>&1; then
    echo "error: tern not found on PATH (requires v$minTernVersion or newer)" >&2
    exit 1
fi

ternVersion=$(tern version 2>/dev/null | sed -n 's/^tern v\([0-9][0-9.]*\).*/\1/p')
if [ -z "$ternVersion" ]; then
    echo "error: unable to determine tern version from 'tern version' (requires v$minTernVersion or newer)" >&2
    exit 1
fi

if [ "$(printf '%s\n%s\n' "$minTernVersion" "$ternVersion" | sort -t. -k1,1n -k2,2n -k3,3n | head -n 1)" != "$minTernVersion" ]; then
    echo "error: tern v$ternVersion is too old, v$minTernVersion or newer is required" >&2
    echo "hint: go install github.com/jackc/tern/v2@latest" >&2
    exit 1
fi

echo "- Applying schema migrations.."
cd schema
tern status --config $TERN_CONF --version-table $schemaVersionTable
tern migrate --config $TERN_CONF --version-table $schemaVersionTable
if [ $? -ne 0 ]; then exit 1; fi
echo "Done"
cd ..

echo "- Loading functions.."
cd functions
tern status --config $TERN_CONF --version-table $functionsVersionTable | grep "version:  1 of 1"
if [ $? -eq 0 ]; then
    tern migrate --config $TERN_CONF --version-table $functionsVersionTable --destination -+1
else
    tern migrate --config $TERN_CONF --version-table $functionsVersionTable
fi
if [ $? -ne 0 ]; then exit 1; fi
echo "Done"
