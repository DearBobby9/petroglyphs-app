#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
check="${1:-all}"
if [[ $# -gt 0 ]]; then shift; fi
destination="${PETROGLYPHS_TEST_DESTINATION:-platform=iOS Simulator,name=iPad Pro 13-inch (M5)}"

run_check() {
    local name="$1"
    shift
    local spec scheme
    case "$name" in
        background) spec=project; scheme=CanvasBackgroundChecks ;;
        canvas) spec=canvas-project; scheme=CanvasDocumentChecks ;;
        markdown) spec=markdown; scheme=MarkdownChecks ;;
        conversation) spec=conversation; scheme=ConversationChecks ;;
        projects) spec=projects; scheme=ProjectChecks ;;
        layout) spec=layout; scheme=CanvasChatLayoutChecks ;;
        reconnect) spec=reconnect; scheme=ReconnectChecks ;;
        ui) spec=simulator-ui; scheme=PetroglyphsSimulatorChecks ;;
        build) scheme=Petroglyphs ;;
        *) echo "Usage: scripts/check.sh [all|build|background|canvas|markdown|conversation|projects|layout|reconnect|ui] [xcodebuild options]" >&2; return 2 ;;
    esac

    mkdir -p "$project_root/build/checks"
    local output
    output="$(mktemp -d "$project_root/build/checks/$name.XXXXXX")"
    local derived_data="$output/DerivedData"
    if [[ -n "${PETROGLYPHS_DERIVED_DATA_ROOT:-}" ]]; then
        mkdir -p "$PETROGLYPHS_DERIVED_DATA_ROOT"
        derived_data="$(mktemp -d "$PETROGLYPHS_DERIVED_DATA_ROOT/$name.XXXXXX")"
    fi
    echo "$name: logs and results in $output"
    if [[ "$name" == build ]]; then
        xcodebuild -project "$project_root/Petroglyphs.xcodeproj" -scheme "$scheme" \
            -destination 'generic/platform=iOS Simulator' -derivedDataPath "$derived_data" \
            CODE_SIGNING_ALLOWED=NO \
            "PETROGLYPHS_SOURCE_COMMIT=$(git -C "$project_root" rev-parse HEAD)" \
            "$@" build 2>&1 | tee "$output/xcodebuild.log"
    else
        command -v xcodegen >/dev/null || { echo 'Install XcodeGen before running XCTest.' >&2; return 1; }
        xcodegen generate --spec "$project_root/Tests/$spec.yml" --project "$project_root/Tests"
        local test_options=(-destination "$destination" -parallel-testing-enabled NO
            -maximum-concurrent-test-simulator-destinations 1)
        if [[ "$name" == markdown ]]; then
            test_options=(-destination 'platform=macOS' -parallel-testing-enabled NO)
        fi
        xcodebuild -project "$project_root/Tests/$scheme.xcodeproj" -scheme "$scheme" \
            "${test_options[@]}" -derivedDataPath "$derived_data" \
            -resultBundlePath "$output/Results.xcresult" CODE_SIGNING_ALLOWED=NO \
            "$@" test 2>&1 | tee "$output/xcodebuild.log"
    fi
}

if [[ "$check" == all ]]; then
    for suite in canvas markdown conversation projects layout reconnect build ui; do
        run_check "$suite" "$@"
    done
else
    run_check "$check" "$@"
fi
