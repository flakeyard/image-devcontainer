# shellcheck shell=bash
# Checks of the current test that the checks of the shell library do not
# have. Source this file after case.sh of the library.
# shellcheck disable=SC2154 # current comes from the harness

# expect_line FILE LINE: FILE has the line LINE.
expect_line() {
  local file=$1 line=$2
  [[ -n $current ]] || return 0
  grep -qxF -- "$line" "$file" || report "no line '$line' in $file: $(cat -- "$file")"
}
