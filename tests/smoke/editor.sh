# shellcheck shell=bash disable=SC2016,SC2034,SC2154 # container commands; output and tests are shared with lib.sh and smoke.sh
# Smoke tests of foreign binaries, project shells and the Dev Containers tools
# (FY-0005). Sourced by scripts/smoke.sh after tests/smoke/lib.sh. Inputs
# (environment): IMAGE; EXPECTED (foreign-libraries); EDITOR_SERVER, an
# unpacked VS Code Server; WORK.

# --- foreign binaries -------------------------------------------------------------

# Libraries every glibc system has; glibc itself serves them.
glibc_libraries='^(libc|libm|libdl|libpthread|librt|libutil|libresolv|ld-linux[^.]*)\.so'
# ELF files the image does not serve, with the reason: Microsoft
# authentication needs X11, which a headless container does not have.
not_served='(msal-node-runtime\.node|libmsalruntime\.so[.0-9]*)$'
# The port of the editor server.
server_port=8000

# without PATTERN: the lines of stdin that do not match the extended regular
# expression PATTERN; that none is left is no error.
without() {
  local pattern=$1
  grep -vE -- "$pattern" || (($? == 1))
}

# needed_libraries ROOT: prints "LIBRARY BINARY" for each library an ELF file
# under ROOT needs, apart from glibc's and the files the image does not serve.
needed_libraries() {
  local root=$1 elf
  find "$root" -type f \( -name node -o -name '*.node' -o -name '*.so*' \) | without "$not_served" |
    while read -r elf; do
      readelf -d "$elf" 2>/dev/null | sed -n "s|.*(NEEDED).*\\[\\(.*\\)\\]|\\1 ${elf##*/}|p"
    done | without "$glibc_libraries"
}

# served LIBRARY: one of the directories of nix-ld has LIBRARY.
served() {
  local library=$1 directory
  for directory in "${directories[@]}"; do
    [[ -e $directory/$library ]] && return 0
  done
  return 1
}

# in_use DIRECTORY: DIRECTORY has one of the needed libraries.
in_use() {
  local directory=$1 library
  for library in $needed; do
    [[ -e $directory/$library ]] && return 0
  done
  return 1
}

# binaries_needing LIBRARY: the binaries that need LIBRARY, on one line.
binaries_needing() {
  local library=$1
  awk -v l="$library" '$1 == l { print $2 }' <<<"$needs" | sort -u | paste -sd' '
}

# server_answers ID: the editor server in the container answers.
server_answers() {
  local id=$1
  docker exec -u dev "$id" curl -fs "http://127.0.0.1:$server_port/version" >/dev/null
}

test_case "nix-ld serves exactly the libraries the editor server needs"
needs=$(needed_libraries "$EDITOR_SERVER")
needed=$(cut -d' ' -f1 <<<"$needs" | sort -u)
mapfile -t directories <"$EXPECTED/foreign-libraries"
for library in $needed; do
  served "$library" || fail "$library is needed but not served, by: $(binaries_needing "$library")"
done
for directory in "${directories[@]}"; do
  in_use "$directory" || fail "$directory is served but no binary needs it"
done

test_case "the editor server starts, also after garbage collection"
start_ready id -v "$EDITOR_SERVER:/srv/server:ro"
collect_garbage "$id"
docker exec -d -u dev "$id" /srv/server/bin/code-server --host 127.0.0.1 --port "$server_port" \
  --without-connection-token --accept-server-license-terms
poll 60 server_answers "$id" || fail "the server did not answer"
remove "$id"

# --- project shells -----------------------------------------------------------------

test_case "direnv enters a project shell with use flake"
cp -R "$tests/../fixture/project" "$WORK/project-shell"
sudo chown -R 1004:1004 "$WORK/project-shell"
run -i -v "$WORK/project-shell:/home/dev/project" -w /home/dev/project -- bash -s <"$probes/project-shell.sh"
expect_line "print-dev-env-ok"
expect_line "variable: from the project shell"
expect_text "ignoring untrusted flake configuration setting 'extra-substituters'"

# --- Dev Containers tools ---------------------------------------------------------

# devcontainer_up ENGINE IMAGE: starts a workspace with a one-line
# devcontainer.json and creates a file in it as the remote user.
devcontainer_up() {
  local workspace=$WORK/workspace-$1
  mkdir -p "$workspace/.devcontainer"
  printf '{ "image": "%s" }\n' "$2" >"$workspace/.devcontainer/devcontainer.json"
  output=$(
    devcontainer up --docker-path "$1" --workspace-folder "$workspace" &&
      devcontainer exec --docker-path "$1" --workspace-folder "$workspace" \
        sh -c 'id -un; nix store info >/dev/null && echo nix-ok; touch created && echo written'
  ) 2>&1
  host_owner=$(stat -c %u "$workspace/created" 2>/dev/null || echo none)
  "$1" ps -aq --filter "label=devcontainer.local_folder=$workspace" | xargs -r "$1" rm -f >/dev/null
}

test_case "the Dev Containers tools start the image with docker"
devcontainer_up docker "$IMAGE"
expect_line "dev"
expect_line "nix-ok"
expect_line "written"
[[ $host_owner == "$(id -u)" ]] || fail "the file belongs to $host_owner on the host"

test_case "the Dev Containers tools start the image with rootless Podman"
# Podman reads this file after the containers.conf files of the runner and its
# user, which stay untouched.
podman_conf=$WORK/containers.conf
printf '[containers]\nuserns = "keep-id:uid=1000,gid=1000"\n' >"$podman_conf"
docker save "$IMAGE" | CONTAINERS_CONF_OVERRIDE=$podman_conf podman load
CONTAINERS_CONF_OVERRIDE=$podman_conf devcontainer_up podman "docker.io/library/$IMAGE"
expect_line "dev"
expect_line "nix-ok"
expect_line "written"
[[ $host_owner == "$(id -u)" ]] || fail "the file belongs to $host_owner on the host"
