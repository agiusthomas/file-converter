#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
cd "$project_dir"
export CLANG_MODULE_CACHE_PATH="$project_dir/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$project_dir/.build/module-cache"
mkdir -p "$project_dir/.build/module-cache" "$project_dir/.build/cache" "$project_dir/.build/config" "$project_dir/.build/security"
swift_command="${1:-build}"
if (( $# > 0 )); then shift; fi
# The package has no plugins or third-party dependencies. Avoid SwiftPM's nested
# manifest sandbox, which cannot start inside the agent's existing sandbox.
exec swift "$swift_command" --disable-sandbox --cache-path "$project_dir/.build/cache" --config-path "$project_dir/.build/config" --security-path "$project_dir/.build/security" "$@"
