# Architecture Decision Records

This directory records the decisions of this repository: the design of the dev
container image, including its public API. Decisions that bind the whole
organization or several repositories are in [flakeyard/decisions][decisions] as
`FY-NNNN`; the records here must not contradict them.

All ADRs live in `records/` as `NNNN-slug.md`. **Files never move.** Numbers are
never reused. Status is stored in frontmatter; `INDEX.md` groups records by
status.

```text
docs/adr/
├── README.md      this file
├── INDEX.md       generated, do not edit by hand
├── template.md    copy into records/ to start a new ADR
└── records/       all ADRs, any status
```

## Statuses

- **proposed**: under discussion.
- **accepted**: in effect; its Constraints are binding.
- **rejected**: considered and declined; kept so the question is not reopened
  blindly.
- **superseded**: replaced; `superseded_by` points to the replacement.
- **deprecated**: no longer relevant, nothing replaces it.

## Title

The title lives in the `title` frontmatter field only; records start with
`## Context`, without a top-level heading.

## Changing status

1. Edit `status` (and `supersedes` / `superseded_by` on both records).
2. Regenerate `INDEX.md`.

## Linking

Inside `records/`, ADRs link to each other with sibling paths, e.g.
`[ADR-0004](0004-short-title.md)`. They stay valid because files do not move.
Records of flakeyard/decisions are named by their full id with a full link, e.g.
[FY-0024][fy-0024].

## Governed code

`affects` lists the files of this repository that a decision governs, as path
globs (`nix/image/**`).

[decisions]: https://github.com/flakeyard/decisions
[fy-0024]:
  https://github.com/flakeyard/decisions/blob/main/docs/adr/records/0024-versioning-and-support.md
