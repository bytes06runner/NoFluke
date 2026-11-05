# Arkiv friction log

Logged as it happens, newest first.

## 2026-11-05 21:20 IST

- **Where:** the team plan versus the SDK.
- **What happened:** our plan called the batch write `mutateEntities`. SDK 1.0.1 and the current docs use `executeBatch`, on a schema-based API (`defineSchema`, `createEntity`). The docs index at `llms.txt` pointed us to the current API quickly.
- **Time lost:** a few minutes, because we caught it before writing code.
- **Suggestion:** a short migration note listing old and new method names would help anyone working from older examples.
