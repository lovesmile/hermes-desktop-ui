# Hermes Desktop Usage Guide

## 1. Connection Modes

Hermes Desktop supports 3 connection modes:

- `local`: run shell and file operations through WSL bridge.
- `embedded`: run shell and file operations through Windows embedded runtime.
- `remote`: run shell and file operations through SSH remote bridge.

At runtime, upper layers do not branch by mode. They call one unified entry:

- `ConnectionManager.runShell(...)`
- `ConnectionManager.startShellProcess(...)` (streaming process, local/embedded)

The mode-specific behavior is isolated in bridge implementations:

- `WslBridge`
- `EmbeddedBridge`
- `RemoteBridge`

## 2. First Launch and Setup

On first launch, the app auto-detects the environment:

1. Checks WSL for Hermes → selects local mode
2. Checks for embedded hermes.exe → selects embedded mode
3. If neither found, shows setup wizard

After setup is saved, app reconnects with the selected mode and refreshes runtime context.

## 3. Mode Switch Behavior

When switching mode in Settings, `ConnectionManager` applies connection context in one place:

- update local database namespace (mode isolation)
- update config mode namespace
- refresh gateway base URL
- update current server id

This ensures mode switching does not require UI/business layer branching.

For local mode, if the gateway is already running and the API_SERVER_KEY hasn't changed,
the restart is skipped.

## 4. Data Isolation Rules

Data that must be isolated by connection mode/server is separated by namespace:

- chat sessions and messages in local desktop DB
- cache and runtime files under mode/server-specific context
- gateway-facing server id bound to current connection

Recommended verification after switching mode:

1. open chat list and verify session set belongs to active mode/server
2. refresh dashboard cards and machine status
3. check logs tab data source
4. check skills/models/config/cron list refresh
5. check file browser root/path switches to current connection home

## 5. Troubleshooting

### `The getter 'HOME' isn't defined`

Cause: Dart string interpolates `$HOME` as a Dart identifier.

Fix: use escaped shell variable in Dart strings:

- `"\$HOME/..."`
- `'echo \$HOME'`

Do not write unescaped `"$HOME"` in Dart string literals.

### Build succeeds but analyze has warnings

Current repository contains historical warnings not introduced by recent changes.
Focus blocking issues first:

- Dart `error`
- build failure
