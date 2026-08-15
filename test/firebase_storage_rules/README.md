# Firebase Storage Rules Tests

Run from repository root:

```powershell
firebase emulators:exec --only storage --project demo-var-app "npm test --prefix test/firebase_storage_rules"
```

Tests use only Firebase Storage emulator and never contact a live Firebase project.
