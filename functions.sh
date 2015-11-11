#!/usr/bin/env bash

[[ "$TRACE" ]] && set -x
set -eo pipefail

haproxy_discover_backend_of() {
	local id="$1"
	local naming_script="${CONFIG_BACKEND_NAMING_SCRIPT:-$(command -v backend-naming)}"
	"$naming_script" "$id"
}

haproxy_discover_address_of() {
	local id="$1"
	shift
}

haproxy_discover_environment_of() {
	local id="$1"
	shift
}

haproxy_discover_labels_of() {
	local id="$1"
	shift
}