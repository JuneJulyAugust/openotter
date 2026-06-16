#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

status=0

echo "Checking Markdown for GitHub math macros that fail to render..."

if rg -n --glob '*.md' '\\operatorname|\\text\{' .; then
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

echo "Checking Markdown display-math delimiter balance..."

while IFS= read -r file; do
  count="$(awk '{ n += gsub(/\$\$/, "") } END { print n + 0 }' "$file")"
  if (( count % 2 != 0 )); then
    echo "$file: odd number of display-math delimiters ($count)"
    status=1
  fi
done < <(rg --files --glob '*.md')

exit "$status"
