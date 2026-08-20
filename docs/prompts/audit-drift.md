# Prompt: Audit project drift

Audit the repository without implementing features.

Compare code, tests, docs, task statuses, and commits against:

- approved product specification;
- implementation plan;
- roadmap and local task records;
- privacy/storage constraints;
- approved Open Design composition;
- test strategy.

Report:

1. product-scope drift;
2. architecture drift;
3. privacy/security drift;
4. design/accessibility drift;
5. test-quality gaps;
6. stale or contradictory task statuses;
7. recommended task/backlog corrections.

Do not create GitHub Issues, write feature code, or mark tasks done. Save the audit under `docs/implementation/audits/` only when the user asked for a durable report.
