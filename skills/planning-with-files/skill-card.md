## Description:

Provides persistent file-based planning for multi-step agent work, with lifecycle hooks that restore selected project context.

This skill is ready for commercial/non-commercial use.

## Publisher:

[othmanadi](https://clawhub.ai/user/othmanadi)

### License/Terms of Use:

MIT-0

## Use Case:

Developers and agent users use the skill to keep plans, findings, and progress in project files across multi-step tasks and sessions. It is intended for work requiring several tool calls, especially five or more.

### Deployment Geography for Use:

Global

## Known Risks and Mitigations:

Risk: Initialization may execute untrusted project code.

Mitigation: Avoid initialization in untrusted projects until Python initialization is isolated.

Risk: PowerShell phase and ledger writers may change another project's planning files.

Mitigation: Avoid these PowerShell writers until their write destinations are validated.

Risk: Copying a template can replace an existing loop.md, while session replay or continuation may expose prior excerpts or continue work unexpectedly.

Mitigation: Back up loop.md before copying the template, and enable replay or continued execution only when intended.

## Reference(s):

- [ClawHub skill release](https://clawhub.ai/othmanadi/skills/planning-with-files)

## Skill Output:

**Output Type(s):** [Markdown, Guidance]

**Output Format:** [Markdown planning files and concise agent guidance]

**Output Parameters:** [1D]

**Other Properties Related to Output:** [Project-scoped planning content that varies with the task.]

## Skill Version(s):

3.25.0 (source: release metadata)

## Ethical Considerations:

Users should evaluate whether this skill is appropriate for their environment, review any generated or modified files before relying on them, and apply their organization's safety, security, and compliance requirements before deployment.
