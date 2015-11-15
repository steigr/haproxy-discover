#!/usr/bin/env bash
TRACE="${TRACE:-$CONFIG_TRACE}"
[[ "$TRACE" ]] && set -x
set -eo pipefail

haproxy_discover_vars() {
	export CONFIG_RELOAD_SCRIPT="${CONFIG_RELOAD_SCRIPT:-/etc/init.d/haproxy}"
	export CONFIG_HAPROXY_CONFIG_PATH="${CONFIG_HAPROXY_CONFIG_PATH:-/etc/haproxy}"
	export HAPROXY_CONFIG_PATH="${HAPROXY_CONFIG_PATH:-$CONFIG_HAPROXY_CONFIG_PATH}"
	export BACKEND_MARKER_PREFIX="${BACKEND_MARKER_PREFIX:-docker_}"
	export BACKEND_DEFAULT_PORT="${BACKEND_DEFAULT_PORT:-8080}"
	export HAPROXY_RELOAD_AFTER_DETACH="${HAPROXY_RELOAD_AFTER_DETACH:-false}"
}

haproxy_discover_inspect() {
  local id="$1"
  local property="$2"
  local args="--unix-socket /var/run/docker.sock http:/containers/$id/json"
  case "$DOCKER_HOST" in
    unix://*)
      args="--unix-socket ${DOCKER_HOST#unix://*} http:/containers/$id/json"
    ;;
    tcp://*)
      args="http://${DOCKER_HOST#tcp://*}/containers/$id/json"
    ;;
  esac
  curl -sL $args | jq -r "$property"
}

haproxy_discover_backend_of() {
	local id="$1"
	local naming_script="${CONFIG_BACKEND_NAMING_SCRIPT:-$(command -v backend-naming)}"
	"$naming_script" "$id"
}

haproxy_discover_address_of() {
	local id="$1"
	haproxy_discover_inspect "$id" ".NetworkSettings.IPAddress"
}

haproxy_discover_port_of() {
	local id="$1"
	haproxy_discover_inspect "$id" ".Config.ExposedPorts" \
	| jq -r 'to_entries | .[0].key' | cut -f1 -d/
}

haproxy_discover_marker_of() {
	local id="$1"
	printf "# ${BACKEND_MARKER_PREFIX}${id}"
}

haproxy_discover_config_template() {
	local backend="$1"
	cat <<EO_CONFIG_TEMPLATE
backend $backend
EO_CONFIG_TEMPLATE
}

haproxy_discover_create_config() {
	local file="$1"
	local backend="$2"
	haproxy_discover_config_template "$backend" \
	| tee "$file"
}

haproxy_discover_add_backend() {
	local file="$1"
	local id="$2"
	local address="$(haproxy_discover_address_of "$id")"
	local port="$(haproxy_discover_port_of "$id")"
	local marker="$(haproxy_discover_marker_of "$id")"
	echo "server $id $address:${port:-$BACKEND_DEFAULT_PORT} check $marker" \
	| tee -a "$file"
}

haproxy_discover_remove_backend() {
	local id="$1"
	find "$HAPROXY_CONFIG_PATH" -type f \
	| xargs -n1 sed -i -e "/$(haproxy_discover_marker_of "$id")/d"
}

haproxy_discover_backend_of() {
  local id="$1"
  if [[ -x "$(command -v "$BACKEND_NAMING_SCRIPT")" ]]; then
    "$(command -v "$BACKEND_NAMING_SCRIPT")" "$id" || exit 1
  else
    local backend="bk_"
    local backend="$backend$(haproxy_discover_inspect "$id" ".Config.Hostname")"
    printf "$backend$(haproxy_discover_inspect "$id" ".Config.Domainname")"
  fi
}

haproxy_discover_reload() {
	"$CONFIG_RELOAD_SCRIPT" reload || true
}

haproxy_discover_attach() {
	local id="$1"
	local backend="$(haproxy_discover_backend_of "$id")"
	[[ "$backend" ]] || exit 0
	echo "Attaching $id to load balancer"
	local backend_config="${CONFIG_HAPROXY_CONFIG_PATH}/${backend}.cfg"
	[[ -f "${backend_config}" ]] \
	|| haproxy_discover_create_config "${backend_config}" "${backend}"
	haproxy_discover_add_backend "${backend_config}" "$id"
	haproxy_discover_reload
}

haproxy_discover_detach() {
	local id="$1"
	echo "Detaching $id to load balancer"
	haproxy_discover_remove_backend "$id"
	[[ "$HAPROXY_RELOAD_AFTER_DETACH" = "true" ]] \
	&& haproxy_discover_reload
}
