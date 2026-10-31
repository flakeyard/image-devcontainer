#!/usr/bin/env bash
# Usage: check-eol EOL_FILE [TODAY]
#
# Warns from 30 days before the end of life of the nixpkgs branch in
# EOL_FILE ("<branch> <YYYY-MM-DD>") and fails after it (FY-0026). Run weekly,
# never as a required check, so that old commits keep passing. Fails on a
# file without exactly one such line.
set -euo pipefail
shopt -s inherit_errexit

eol_file=$1
today=${2-$(date -u +%F)}
branch_pattern='^nixos-[0-9]{2}\.[0-9]{2}$'
date_pattern='^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
comment_pattern='^[[:space:]]*(#|$)'
warning_days=30
seconds_per_day=86400

# malformed PROBLEM: fails on an EOL file that cannot be read.
malformed() {
  local problem=$1
  echo "::error::$eol_file: $problem; it needs one line \"nixos-YY.MM YYYY-MM-DD\"."
  exit 1
}

# epoch DAY: the seconds since 1970 of DAY, a valid date YYYY-MM-DD.
epoch() {
  local day=$1
  [[ $day =~ $date_pattern ]] && date -u -d "$day" +%s 2>/dev/null
}

# data_lines FILE: the lines of FILE that are neither comments nor blank.
data_lines() {
  local file=$1 line
  while IFS= read -r line || [[ -n $line ]]; do
    [[ $line =~ $comment_pattern ]] || printf '%s\n' "$line"
  done <"$file"
}

lines=$(data_lines "$eol_file")
[[ -n $lines ]] || malformed "no data line"
[[ $lines != *$'\n'* ]] || malformed "more than one data line"
read -r branch eol extra <<<"$lines"
[[ $branch =~ $branch_pattern ]] || malformed "'$branch' is not a branch nixos-YY.MM"
[[ -z $extra ]] || malformed "unexpected '$extra' after the date"
eol_epoch=$(epoch "$eol") || malformed "'$eol' is not a date YYYY-MM-DD"
today_epoch=$(epoch "$today") || {
  echo "::error::'$today' is not a date YYYY-MM-DD."
  exit 2
}

days=$(((eol_epoch - today_epoch) / seconds_per_day))
if ((days < 0)); then
  echo "::error::$branch reached its end of life on $eol; switch to the next stable branch."
  exit 1
elif ((days <= warning_days)); then
  echo "::warning::$branch reaches its end of life on $eol, in $days days; switch to the next stable branch."
else
  echo "$branch is supported until $eol, $days days from $today."
fi
