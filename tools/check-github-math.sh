#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

status=0

echo "Checking Markdown for GitHub math macros that fail to render..."

macro_output=""
while IFS= read -r file; do
  file_output="$(
    perl -ne '
    $line++;
    if (/^\s*```/) {
      $in_fence = !$in_fence;
      next;
    }
    next if $in_fence;
    s/`[^`]*`//g;
    if (/\\operatorname|\\text\{/) {
      print "$ARGV:$line:$_";
    }
    ' "$file"
  )"
  if [[ -n "$file_output" ]]; then
    macro_output+="$file_output"$'\n'
  fi
done < <(rg --files --glob '*.md')

if [[ -n "$macro_output" ]]; then
  printf '%s\n' "$macro_output"
  cat <<'MSG'

Unsupported math macro found.

GitHub's math renderer rejects some LaTeX macros in Markdown. Prefer forms
that have rendered in GitHub previews for this repo:

  \mathrm{atan2}(x,y)     instead of \operatorname{atan2}(x,y)
  \mathrm{clip}(x,0,1)    instead of \operatorname{clip}(x,0,1)
  \mathrm{diag}(...)      instead of \operatorname{diag}(...)

Avoid \text{...} inside display math; use prose, tables, or symbols with
definitions nearby.
MSG
  status=1
fi

echo "Checking Markdown for fragile inline frame-notation math..."

inline_output=""
while IFS= read -r file; do
  file_output="$(
    perl -ne '
    $line++;
    if (/^\s*```/) {
      $in_fence = !$in_fence;
      next;
    }
    next if $in_fence;
    s/`[^`]*`//g;
    if (/\$\{\}\^\{[A-Za-z]/) {
      print "$ARGV:$line:$_";
    }
    ' "$file"
  )"
  if [[ -n "$file_output" ]]; then
    inline_output+="$file_output"$'\n'
  fi
done < <(rg --files --glob '*.md')

if [[ -n "$inline_output" ]]; then
  printf '%s\n' "$inline_output"
  cat <<'MSG'

Fragile inline frame notation found.

GitHub may fail to render inline math that starts with `${}^{...}`. Prefix
frame-notation inline math with a leading math spacing command:

  $\!{}^{M}\mathbf{e}_{x_B}$   instead of ${}^{M}\mathbf{e}_{x_B}$

For full equations, prefer display math on its own `$$` lines.
MSG
  status=1
fi

echo "Checking Markdown display-math delimiter balance..."

delimiter_output=""
while IFS= read -r file; do
  count="$(
    perl -ne '
    if (/^\s*```/) {
      $in_fence = !$in_fence;
      next;
    }
    next if $in_fence;
    s/`[^`]*`//g;
    $count += () = /\$\$/g;
    END { print $count + 0; }
    ' "$file"
  )"
  if (( count % 2 != 0 )); then
    delimiter_output+="$file: odd number of display-math delimiters ($count)"$'\n'
  fi
done < <(rg --files --glob '*.md')

if [[ -n "$delimiter_output" ]]; then
  printf '%s\n' "$delimiter_output"
  status=1
fi

exit "$status"
