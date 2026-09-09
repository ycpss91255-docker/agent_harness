#!/usr/bin/env bash
# init.sh - forwarder to dist/script/harness/init.sh
#
# NOT THE IMPLEMENTATION. It exists so that the path consumers type stays
# valid however dist/ is reorganised later. base learned this the hard way:
# moving upgrade.sh into dist/ meant an upgrade deleted the command that
# performs upgrades, and the next one exited 127 against a repo that was
# otherwise fine -- a failure that only appears one release late.
#
# Deliberately the most boring thing that can work: resolve the sibling
# path, exec, done. It holds no logic, so it cannot drift.
set -euo pipefail
here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
exec "${here}/dist/script/harness/init.sh" "$@"
