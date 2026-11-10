# shellcheck shell=bash
# Checks of the current test that the checks of the shell library do not
# have. Source this file after case.sh of the library.
# shellcheck disable=SC2154 # work, current and registry come from the harness

# expect_calls TEXT: the calls of the stubs, joined by ';', are TEXT.
expect_calls() {
  local text=$1 calls
  [[ -n $current ]] || return 0
  calls=$(paste -sd';' "$work/calls")
  [[ $calls == "$text" ]] || report "calls '$calls', expected '$text'"
}

# expect_line FILE LINE: FILE has the line LINE.
expect_line() {
  local file=$1 line=$2
  [[ -n $current ]] || return 0
  grep -qxF -- "$line" "$file" || report "no line '$line' in $file: $(cat -- "$file")"
}

# expect_tag TAG DIGEST: the tag TAG of the registry points at DIGEST.
expect_tag() {
  local tag=$1 digest=$2 tagged
  [[ -n $current ]] || return 0
  tagged=$(cat -- "$registry/tags/$tag" 2>/dev/null)
  [[ $tagged == "$digest" ]] || report "tag $tag is '$tagged', expected '$digest'"
}
