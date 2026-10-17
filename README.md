# Petroglyphs iPad App

Production sources are in `Petroglyphs/`. Xcode includes that folder through a
`PBXFileSystemSynchronizedRootGroup`. `Petroglyphs.xcodeproj` is the production
project. `Tests/*.yml` generate isolated XCTest projects using the same sources.
The unused duplicate sources from the repository root have been removed.

The bridge implementation and API documentation are in the sibling
[`petroglyphs-mcp`](../petroglyphs-mcp) repository. Local project creation uses the
native creator. Remote project creation uses the configured companion route.
Creation receipts retain their original route during recovery.

The app discovers compatible Mac bridges over Tailscale and Bonjour. Select a
Mac, compare its six-digit code, and approve on that Mac. Pairing does not need
a cable or manual address entry. The connection page distinguishes the network
route from the selected Codex execution machine. The canvas supports four-way
navigation, 25%–400% zoom, and saved viewports. See the
[connection and canvas guide](docs/WIRELESS-AND-CANVAS.md) for installation setup,
daily use, and the numeric precision boundary.

The [2026-10-17 progress and TODO](docs/PROGRESS-2026-10-17.md) records completed
device checks and the remaining layout stall with a saved image draft. Cross-Mac
round-trip acceptance is still incomplete.

## Checks

Requirements: Xcode with an iOS Simulator runtime, and XcodeGen for XCTest.
Run from this repository:

```sh
bash scripts/check.sh build
bash scripts/check.sh conversation
bash scripts/check.sh projects
bash scripts/check.sh background
bash scripts/check.sh canvas
bash scripts/check.sh markdown
bash scripts/check.sh layout
bash scripts/check.sh reconnect
bash scripts/check.sh ui
bash scripts/check.sh all
```

Use a smaller check after a scoped change. Use `all` for an integration gate.
The canvas suite includes background export coverage, so `all` runs that coverage once.
Markdown parser checks run as macOS XCTest. The remaining test suites use iOS Simulator.
The UI suite uses its own app container and checks canvas editing, persistence,
connection cancellation and large-text rotation. Simulator drawing accepts mouse
or touch input; physical iPads keep Pencil-only drawing.
Additional arguments pass to `xcodebuild`, such as
`-only-testing:ConversationTests/CodexConversationStoreTests`.
Set `PETROGLYPHS_TEST_DESTINATION` to select an installed simulator:

```sh
PETROGLYPHS_TEST_DESTINATION='platform=iOS Simulator,name=iPad Air 13-inch (M4)' \
  bash scripts/check.sh conversation
```

XcodeGen writes ignored test projects beside the source manifests in `Tests/`.
Each invocation writes logs, derived data and XCTest result bundles under the
ignored `build/checks/` directory. A nonzero command exit means
the check failed. The build command records the source Git commit in the app's
`PetroglyphsSourceCommit` Info.plist key.

If macOS restricts the test runner from opening a bundle under Desktop, set
`PETROGLYPHS_DERIVED_DATA_ROOT=/tmp/PetroglyphsChecks`. Test binaries then build
outside that protected folder while logs and result bundles stay in `build/checks/`.

Build and XCTest results establish source and simulator behavior. They do not
establish physical iPad Pencil, keyboard, VoiceOver or remote Mac behavior.
Track implementation commits and acceptance evidence in
[`docs/REVIEW-REMEDIATION-PLAN.md`](docs/REVIEW-REMEDIATION-PLAN.md).
