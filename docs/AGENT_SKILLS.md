# Ate agent skills

## Purpose

Ate keeps reusable coding-agent guidance in the repository so that compatible agents can discover the same project conventions and specialist workflows. The skills are documentation/instruction resources; they do not add runtime app behavior.

## Location and format

Skills live at:

```text
.agents/
└── skills/
    └── <skill-name>/
        └── SKILL.md
```

Each `SKILL.md` begins with YAML frontmatter containing:

- `name`: lowercase skill identifier; match the containing directory.
- `description`: concise explanation of the work that should trigger the skill.

Keep the body action-oriented: when to use the skill, what to inspect, constraints, implementation guidance, verification, and delivery evidence. Put substantial supporting material in a nearby `references/` directory and link it from the skill rather than making the entrypoint unwieldy.

## Current catalogue

| Skill | Use for |
| --- | --- |
| `ate-architecture` | Architecture, data ownership, module boundaries, cross-feature changes |
| `ate-swiftui` | SwiftUI UI, navigation, interaction states, accessibility |
| `ate-testing` | XCTest, simulator/CI diagnosis, verification evidence |
| `ate-journal` | Journal persistence, lifecycle, archive/recovery, consumers |
| `ate-integrations` | App Intents, Apple platform surfaces, AI and external integrations |
| `ate-release-readiness` | PR quality, CI gates, rollout, release acceptance |

## Instruction precedence

1. Repository-wide rules in the root `AGENTS.md` apply to all work.
2. Read the relevant specialist skill for work in its domain.
3. A skill supplements repository instructions; it cannot override security, privacy, data-integrity, testing, or delivery requirements.
4. When guidance conflicts with verified code or current platform behavior, inspect the implementation and update the documentation through review rather than following stale instructions.

## Xcode and agent compatibility

These files are ordinary Markdown resources in the Git repository. They are not an Apple `.bundle`, framework, Swift package, Xcode project group, or app resource, and they do not need to be added to a Copy Bundle Resources build phase.

The `.agents/skills/` convention is used by compatible coding agents that implement the Agent Skills discovery convention. Xcode's built-in coding agent has its own supported customization and discovery behavior, which can vary by Xcode version. Do not assume that every Xcode release automatically discovers this directory. Verify discovery in the installed Xcode version and use its documented agent customization mechanism when needed. Keeping the source in Git still makes the guidance available to other compatible tools and to developers reading the repository.

## Maintenance

- Keep each skill focused on a coherent workflow.
- Prefer durable project rules over temporary incident notes.
- Include exact commands only when verified against the repository.
- Review skill changes like code: explain the rationale and update references when conventions change.
- Never place credentials, secrets, private user data, or production data in skill files.
