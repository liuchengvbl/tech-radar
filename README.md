[中文](README_ZH.md)

# tech-radar — Tech Frontier Intelligence Agent

An automated tech intelligence collection system. It schedules AI agents via cron to scan the latest developments in specified domains and generate structured daily/weekly/monthly reports.

Supports multiple platforms (Claude Code / OpenCode / Kiro-CLI) — the same set of prompts and configs can run across platforms.

## Features

- **Daily Report**: Automatically scans multiple tech domains each day, generating Markdown reports with cited sources
- **Weekly Report**: Aggregates the week's daily reports and plots signal trend charts (TEM four-quadrant model)
- **Monthly Report**: In-depth trend analysis, including Hype Cycle phase determination, TRL assessment, and config modification suggestions
- **Multi-Instance**: The same set of scripts can drive multiple instances for different domains (e.g. sensor, robotics, biotech)

## Directory Structure

```
tech-radar-port/
├── core/                           # Platform-agnostic core assets
│   ├── agent-prompt.md             #   Generic agent system prompt (no specific tool names)
│   ├── daily.prompt.md             #   Daily report prompt template
│   ├── weekly.prompt.md            #   Weekly report prompt template
│   ├── monthly.prompt.md           #   Monthly report prompt template
│   ├── review-config.sh            #   Monthly config review helper script
│   ├── SKILL.md                    #   System maintenance skill doc
│   └── skills/                     #   Bundled skill files
│       ├── arxiv-search/
│       ├── deep-research/
│       ├── environmental-scanning-foresight/
│       ├── evaluating-new-technology/
│       └── rss-agent-discovery/
│
├── instance-template/
│   ├── instance.env.template       #   Instance config template (paths, model, timeouts)
│   └── scan-config.example.yaml    #   Scan domain config example
│
├── platforms/                      # Platform adaptation layer
│   ├── PORTING-GUIDE.md            #   Full guide for porting to a new platform (AI-agent oriented)
│   ├── claude-code/                #   Claude Code adapter
│   │   ├── agent.md                #     Agent definition (frontmatter + tool mapping)
│   │   ├── daily.sh / weekly.sh / monthly.sh
│   │   ├── hooks/                  #     shell-guard + write-guard
│   │   └── README.md
│   ├── opencode/                   #   OpenCode adapter
│   │   ├── agent.md
│   │   ├── daily.sh / weekly.sh / monthly.sh
│   │   ├── glm-websearch-proxy.js  #     GLM/GPT web_search proxy (optional)
│   │   ├── glm-websearch-proxy.service
│   │   └── README.md
│   └── kiro-cli/                   #   Kiro-CLI adapter
│       ├── agent.md
│       ├── daily.sh / weekly.sh / monthly.sh
│       └── README.md
│
├── setup.sh                        # Interactive install wizard
├── LICENSE
└── README.md
```

## Quick Start

```bash
git clone <repo-url> tech-radar-port
cd tech-radar-port
bash setup.sh
```

The install wizard will ask for:
1. Target platform (Claude Code / OpenCode / Kiro-CLI)
2. Agent install directory
3. Instance name (e.g. `sensor`)
4. Report output directory
5. Whether to auto-write crontab entries

## Configuration

After installation, edit the `scan-config.yaml` in the instance directory:

- `domains`: Define scan domains, keywords, and entities to track
- `budget.mode`: `unlimited` / `standard` / `economy` (controls token consumption)
- `sources`: Fixed URLs of information sources to patrol
- `signals`: Auto-maintained by the weekly report, records trend signal status

`instance.env` controls runtime parameters (timeouts, model, output paths).

> **Output Language**: The output language of reports is controlled by the `scan-config.yaml` → `meta.output_language` field, which can be set to `Chinese` or `English`.

## Manual Run

```bash
# Daily report
bash <install_dir>/scripts/daily.sh <instance_dir>

# Weekly report
bash <install_dir>/scripts/weekly.sh <instance_dir>

# Monthly report
bash <install_dir>/scripts/monthly.sh <instance_dir>
```

## Porting to a New Platform

If your target platform is not in the supported list, refer to [platforms/PORTING-GUIDE.md](platforms/PORTING-GUIDE.md).
The guide is AI-agent oriented and includes the full research, adaptation, testing, and troubleshooting workflow.

## Dependencies

| Dependency | Install Method |
|------------|----------------|
| Python 3 | Pre-installed on most systems, or `apt install python3` |
| pyyaml | `pip3 install pyyaml` |
| arxiv | `pip3 install arxiv` |
| AI coding platform CLI | Any one of Claude Code / OpenCode / Kiro-CLI |
