## What changes and why

<!-- e.g. "Grant release-bot access to service-c for the Q4 release train (SEC-123)" -->

## Checklist

- [ ] The plan comment shows exactly the access change I intended: no unexpected `+` or `−`
- [ ] The owning team agrees (link):
- [ ] **New app:** installed on `app-quarantine` only, and `inventory/inventory.json` regenerated in this PR
- [ ] **Decommission step 1** (`status: quarantined`): dependencies checked: required checks from this app, bypass, secrets, webhooks (docs/GOVERNANCE.md)
- [ ] **Decommission step 2** (YAML deleted): the app was quarantined and suspended for 14+ days without complaints
