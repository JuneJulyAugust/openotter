#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

bad_md="$tmp_dir/bad.md"
good_md="$tmp_dir/good.md"

cat > "$bad_md" <<'MD'
# Bad Math

$$
\kappa \approx
\frac{\mathrm{wrapToPi}(\psi_{\mathrm{after}}-\psi_{\mathrm{before}})}
\ell_{\mathrm{arc}}}
$$
MD

cat > "$good_md" <<'MD'
# Good Math

$$
\kappa \approx
\frac{\mathrm{wrapToPi}(\psi_{\mathrm{after}}-\psi_{\mathrm{before}})}
{\ell_{\mathrm{arc}}}
$$
MD

if "$repo_root/tools/check-github-math.sh" "$bad_md" > "$tmp_dir/bad.out" 2>&1; then
  echo "Expected malformed display math to fail"
  cat "$tmp_dir/bad.out"
  exit 1
fi

if ! rg -q "Unbalanced braces in display math" "$tmp_dir/bad.out"; then
  echo "Expected brace-balance diagnostic"
  cat "$tmp_dir/bad.out"
  exit 1
fi

"$repo_root/tools/check-github-math.sh" "$good_md" > "$tmp_dir/good.out"
