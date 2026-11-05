## Description:

Build, audit, and repair web content against WCAG 2.2. Use when: (1) creating accessible HTML/CSS/JS, (2) remediating accessibility defects, (3) running reproducible automated audits, (4) preparing WCAG 2.2 AAA evidence and human-test records, or (5) running the optional AI-WCAG-Gauntlet benchmark.

This skill is ready for commercial/non-commercial use.

## Publisher:

[turbolego](https://clawhub.ai/user/turbolego)

### License/Terms of Use:

MIT

## Use Case:

Web developers and accessibility practitioners use this skill to build and repair web content, run repeatable WCAG 2.2 audits, and document manual testing for AA or AAA targets.

### Deployment Geography for Use:

Global

## Known Risks and Mitigations:

Risk: Browser audits load the target URL, redirects, and third-party subresources, then save fetched HTML and reports that may be overwritten.

Mitigation: Audit authorized local or staging sites, use a dedicated output directory, and avoid sensitive HTML inputs or output paths.

Risk: The audit wrapper disables Chrome sandboxing in CI when CI is true and AXE_CHROME_EXTRA_ARGS is unset.

Mitigation: Keep sandboxing enabled outside isolated CI; set AXE_CHROME_EXTRA_ARGS to an empty value to preserve it in CI.

Risk: Automated scans and static inventories cannot establish AAA conformance or confirm dynamic interaction behavior.

Mitigation: Complete the manual test protocol and evidence matrix for AAA, and test each user-triggered state change before making conformance claims.

Risk: The release artifact does not include a package manifest or lockfile to establish the referenced dependency versions.

Mitigation: Install reviewed dependency versions before running the audit tools.

## Reference(s):

- [Project homepage](https://github.com/turbolego/wcag-skill)
- [ClawHub release](https://clawhub.ai/turbolego/skills/wcag-skill)
- [W3C WCAG 2.2 Quick Reference](https://www.w3.org/WAI/WCAG22/quickref/)
- [Validator workflow](references/validator-workflow.md)
- [AAA evidence matrix](references/aaa-evidence-matrix.md)
- [Manual test protocol](references/manual-test-protocol.md)
- [Dynamic state test protocol](references/dynamic-state-test-protocol.md)

## Skill Output:

**Output Type(s):** [Guidance, Code, Shell commands, Markdown reports]

**Output Format:** [Markdown guidance with HTML/CSS/JavaScript examples, shell commands, audit reports, and test records]

**Output Parameters:** [1D]

**Other Properties Related to Output:** [May include accessibility code changes, automated audit findings, and manual test evidence; automated results alone do not establish WCAG conformance.]

## Skill Version(s):

2.0.30 (source: frontmatter)

## Ethical Considerations:

Users should evaluate whether this skill is appropriate for their environment, review any generated or modified files before relying on them, and apply their organization's safety, security, and compliance requirements before deployment.
