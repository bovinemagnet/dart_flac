#!/usr/bin/env bash
# Create the maintenance issues identified for dart_flac.
#
# Requires an authenticated GitHub CLI:
#   gh auth login -h github.com

set -euo pipefail

gh auth status >/dev/null

create_issue() {
  local title="$1"
  local body="$2"
  gh issue create --title "$title" --body "$body"
}

create_issue "Add GitHub Actions CI" "$(cat <<'EOF'
Add repository CI that runs the same checks expected before release.

Acceptance criteria:
- Run `dart pub get`.
- Run `dart format --set-exit-if-changed .`.
- Run `dart analyze`.
- Run `dart test`.
- Run `dart test -p chrome test/web_smoke_test.dart`.
- Run `dart pub publish --dry-run`.
EOF
)"

create_issue "Expand conformance and malformed FLAC tests" "$(cat <<'EOF'
Broaden decoder coverage beyond the current happy-path fixtures.

Acceptance criteria:
- Add malformed metadata tests, including truncated headers and invalid block sizes.
- Add coverage for edge cases around ID3v2 tags and SEEKTABLE parsing.
- Keep small byte-layout fixtures inline where they clarify parser behavior.
- Continue using `test/fixtures/` for realistic encoder-generated streams.
EOF
)"

create_issue "Stream flac2wav output for lower memory use" "$(cat <<'EOF'
Reduce peak memory in the CLI converter by writing WAV output incrementally.

Acceptance criteria:
- Avoid decoding all frames before writing when total sample count is known.
- Preserve the existing command shape.
- Keep `--verify` behavior intact.
- Add tests or smoke coverage for generated WAV headers/chunks.
EOF
)"

create_issue "Add coverage reporting" "$(cat <<'EOF'
Add a documented coverage workflow for local development and CI readiness.

Acceptance criteria:
- Add `coverage` as a dev dependency.
- Provide a script or documented command that writes `coverage/lcov.info`.
- Ignore generated coverage artifacts in git and pub publishing.
EOF
)"

create_issue "Add stronger CLI conversion options" "$(cat <<'EOF'
Make `flac2wav` more useful for debugging and partial conversion workflows.

Acceptance criteria:
- Add output bit-depth selection.
- Add start-sample selection.
- Add duration-in-samples selection.
- Support explicit MD5 verification enable/disable flags.
- Document the flags in CLI help.
EOF
)"

create_issue "Polish public API documentation" "$(cat <<'EOF'
Improve docs on exported APIs so users can understand output formats and platform behavior without reading implementation files.

Acceptance criteria:
- Clarify `FlacReader` usage examples.
- Document lazy frame and PCM chunk behavior.
- Document WAV helper output format, including 8-bit WAV unsigned bias.
- Keep implementation-only APIs under `lib/src/` unless intentionally exported.
EOF
)"

create_issue "Add benchmark JSON output and baseline regression checks" "$(cat <<'EOF'
Make benchmark results easier to automate and compare across changes.

Acceptance criteria:
- Add machine-readable JSON output.
- Add a baseline comparison mode.
- Allow configuring the maximum accepted regression percentage.
- Document the workflow in the README.
EOF
)"
