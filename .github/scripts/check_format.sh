#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
git ls-files -z -- 'lib/*.dart' 'lib/**/*.dart' 'test/*.dart' 'test/**/*.dart' \
  | xargs -0 -r -n 100 dart format --
git diff -- lib test
exit 1
