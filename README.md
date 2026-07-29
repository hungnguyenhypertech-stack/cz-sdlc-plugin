# cz-harness-local — CZ-Harness plugin marketplace

This repo is a [Claude Code plugin marketplace](https://docs.claude.com/en/docs/claude-code/plugins) containing one plugin: **[cz-harness](cz-harness/)** — an AI-native delivery Harness for FPT project managers (RD-driven, fully traceable, real-time observable). See [cz-harness/README.md](cz-harness/README.md) for what the plugin actually does, and [cz-harness/docs/OPERATOR-GUIDE.md](cz-harness/docs/OPERATOR-GUIDE.md) for a day-one walkthrough.

## Install

From inside Claude Code:

```
/plugin marketplace add <this-repo-url-or-local-path>
/plugin install cz-harness@cz-harness-local
```

- `<this-repo-url-or-local-path>` is either this repo's GitHub URL (e.g. `owner/repo` or the full clone URL) once pushed, or a local filesystem path to this folder if you're installing straight from a clone/download without publishing it anywhere.
- `cz-harness-local` is this marketplace's name, from [`.claude-plugin/marketplace.json`](.claude-plugin/marketplace.json) — match it if you rename the marketplace.

After installing, run `/cz:init <project-code>` inside the project you want to run CZ-Harness on to scaffold its per-project runtime (`rd/`, `state/`, `telemetry/`, `gate-records/`, `deliverables/`) — none of that is part of this plugin package; it's generated fresh per project.

## Repo layout

```
.claude-plugin/marketplace.json   # marketplace manifest — lists cz-harness below
cz-harness/                        # the plugin itself
├── .claude-plugin/plugin.json     # plugin manifest
├── agents/ commands/ skills/      # 10 subagents, 21 slash commands, 7 skills
├── hooks/                         # enforcing hooks + hooks/tests/ (self-test suite)
├── config/ schemas/ templates/    # gate/delegation/routing config, JSON schemas, artifact templates
├── board/board.html               # single-file live board
└── docs/                          # operator guide, traceability, security notes, ...
```

## Verifying before you install

The plugin ships its own hook self-tests (not run automatically by Claude Code — run manually to sanity-check the enforcement hooks work on your platform, since several past bugs here were shell-portability issues between GNU/BSD tools):

```bash
cd cz-harness
for t in hooks/tests/*.sh; do bash "$t"; done
```

All 8 scripts / 73 assertions should pass. See `CZ-HARNESS-AUDIT-2026-07-29.md` (one level up, outside this marketplace folder, in the working project this was built from) for the full build/audit history if you have access to it.
