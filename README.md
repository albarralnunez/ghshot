# ghshot

A tiny, **dependency-free** skill to upload images (screenshots, diagrams) to GitHub PRs, issues, and comments from the terminal — and get markdown-ready URLs back.

GitHub has no API for attaching images and `gh` can't do it ([cli/cli#4745](https://github.com/cli/cli/discussions/4745)). `ghshot` fills the gap with a single bash script that needs **only an authenticated `gh` CLI** — no node, no npm, no session cookie. Images are stored as release assets on a dedicated public `<you>/ghshot-images` repo (auto-created on first use), giving permanent GitHub-hosted URLs that render in any markdown context.

This is a clean-room bash reimplementation of the GitHub-release backend of [vipulgupta2048/gitshot](https://github.com/vipulgupta2048/gitshot), packaged as a skill.

## Install (skills.sh)

```bash
npx skills add albarralnunez/ghshot
```

Your agent (Claude Code, Codex, Cursor, …) then knows to use it whenever you ask to attach a screenshot to a PR.

## Use directly

```bash
bash skills/ghshot/ghshot.sh shot.png                 # print markdown ![](…)
bash skills/ghshot/ghshot.sh --pr 42 shot.png         # upload + comment on PR #42
bash skills/ghshot/ghshot.sh --issue 10 bug.png       # upload + comment on issue #10
bash skills/ghshot/ghshot.sh --raw shot.png           # raw URL only
bash skills/ghshot/ghshot.sh --json shot.png          # JSON, for scripting/agents
```

## Requirements

- [`gh`](https://cli.github.com) installed and authenticated (`gh auth login`).

## Warning

The `ghshot-images` repo is **public** — anyone with a URL can view uploads. Do not upload sensitive images.

## License

MIT
