# Project rules for the AI coding agent
- Read SPEC.md fully before starting any task. It is the contract.
- Stack, schema, API paths, WebSocket events and state machine are fixed. Propose changes in docs/DECISIONS.md, do not silently diverge.
- Build one phase at a time (SPEC.md Section 20). Do not implement "Later" features.
- Every backend change ships with tests. Run `npm test` and `npm run lint` before declaring done.
- Never commit secrets. Update .env.example when adding config.
- Keep CHANGELOG.md and Swagger in sync with code.
- When unsure about a product rule, ask; when unsure about a library, prefer the one in SPEC.md Section 2.
