#!/bin/sh
set -eu

if ! command -v docker > /dev/null 2>&1; then
    printf '%s\n' 'Docker is required to build this image.' >&2
    exit 1
fi

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
source_revision=$(git -C "$repo_root" rev-parse HEAD 2>/dev/null || true)

exec docker build \
    --file "$repo_root/Dockerfile" \
    --tag "${IMAGE_NAME:-epinelps:latest}" \
    --build-arg "SOURCE_REVISION=$source_revision" \
    "$@" \
    "$repo_root"
