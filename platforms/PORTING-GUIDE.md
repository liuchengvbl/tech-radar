[中文](PORTING-GUIDE_ZH.md)

---
# tech-radar Platform Porting Guide

This guide is intended for AI agents. If you are an agent executing a porting task, read this file in full and then follow the steps.

## Porting Goal

Port tech-radar from a supported platform (Claude Code / OpenCode / Kiro-CLI) to a new AI coding platform.
Once porting is complete, the new platform should be able to generate daily/weekly/monthly reports automatically via cron scheduling, with output formats consistent with the existing platforms.

## Porting Boundaries

**What needs to be ported** (platform-specific):
- Agent definition files (frontmatter format, permission configuration)
- CLI invocation scripts (the agent invocation commands in daily.sh / weekly.sh / monthly.sh)
- Tool mapping (mapping search/fetch/write/execute in prompts to the target platform's specific tool names)

**What does NOT need to be ported** (platform-agnostic):
- All prompt templates under core/ (daily.prompt.md, etc.)
- core/agent-prompt.md (the generic system prompt, contains no specific tool names)
- scan-config and instance.env templates under instance-template/
- All skill files under skills/
- review-config.sh

## Porting Workflow

### Step 1: Platform Capability Research

Before starting, research the following capabilities of the target platform. Each item must have a clear conclusion; anything uncertain must be tested in practice.

#### 1.1 Non-interactive CLI Invocation

Research questions:
- What is the platform's CLI command? (e.g., `claude --print`, `opencode run`, `kiro-cli chat --no-interactive`)
- How do you specify an agent? (`--agent` parameter? a config file?)
- How do you specify a model? (`--model` parameter? is the format an alias or `provider/model-id`?)
- How do you auto-approve permissions? (`--auto`? `--dangerously-skip-permissions`? or no such mechanism?)
- Is the output sent to stdout, or does it require a special flag?

Verification method: execute a minimal prompt (e.g., "What is 1+1?") and confirm you receive the correct text response.

#### 1.2 Agent Definition Mechanism

Research questions:
- Where are agent definition files stored? (project-level `.claude/agents/`? global `~/.config/opencode/agents/`?)
- What is the file format? (Markdown + YAML frontmatter? JSON?)
- What are the required fields? (name? description? mode? model? tools/permission?)
- How do you specify a model? (hardcoded in frontmatter? or overridden at runtime via `--model`?)
- How do you control tool permissions? (whitelist? blacklist? a permission-rule object?)

Verification method: create a minimal agent (description="test"), run it via the CLI with that agent specified, and confirm the agent's prompt takes effect.

#### 1.3 Web Search Capability

This is the most critical capability difference point in porting.

Research questions:
- Does the platform have a built-in `websearch` (open-ended search that does not require a URL)?
- What are the conditions to enable it? (available by default? requires an environment variable? requires configuring a search provider?)
- Does the platform have a built-in `webfetch` (fetch the content of a specified URL)?
- Does the model itself support native web_search (e.g., GLM-5.2's `tools: [{"type":"web_search"}]`)? Does the platform pass through that parameter?

Verification method:
- Test websearch: send "What is the weather in Beijing today?" and see whether the model invokes a search tool and returns real-time information
- Test webfetch: send "Fetch the content of https://example.com" and see whether it can read the webpage
- If neither is available, record the fallback plan (see Section 1.6)

#### 1.4 File Writing Capability

Research questions:
- What is the name and invocation method of the write tool? (`Write`? `write`? `apply_patch`?)
- Is it a full overwrite, or does it support append?
- Is there a single-write line limit?
- Are additional tools needed? (e.g., `apply_patch` for multi-file patch-style editing)

Verification method: use the agent to create a test file, write 10 lines of content, then read it back to confirm the content is consistent.

#### 1.5 Shell Command Execution

Research questions:
- What is the name of the shell tool? (`Bash`? `bash`? `shell`?)
- Is there a command filtering/hook mechanism?
- Can Python scripts be executed via the shell?

Verification method: have the agent execute `python3 -c "print(1+1)"` and confirm it outputs "2".

#### 1.6 Fallback Plan Evaluation (only when websearch/webfetch is unavailable)

If the target platform does not support websearch or webfetch, you need to evaluate fallback paths:

**Plan A: Construct a search URL + webfetch**
If the platform has webfetch but not websearch, you can instruct the model in the agent's tool-mapping notes to use webfetch to access a search engine URL:
- DuckDuckGo HTML: `https://html.duckduckgo.com/html/?q=QUERY&df=d` (df=d/w/m controls the time range)
- arXiv search: `https://arxiv.org/search/?query=QUERY&searchtype=all&order=-announced_date_first`
- Google News RSS: `https://news.google.com/rss/search?q=QUERY&hl=en-US&gl=US&ceid=US:en`

**Plan B: curl + shell**
If the platform has neither websearch nor webfetch, but has a shell, you can use curl. Note that you need to allow curl in the agent's shell permissions, and configuring a domain whitelist is recommended.

**Plan C: Model-native web_search**
If the model itself supports native web_search (e.g., GLM-5.2, GPT-5.5), but the platform's provider adapter does not pass through that parameter, you can deploy a local HTTP proxy that injects the `web_search` tool. See `platforms/opencode/glm-websearch-proxy.js`.

After choosing a fallback plan, append a tool-mapping note to the platform-adapted agent.md, clearly telling the model how to search and fetch webpages.

### Step 2: Create the Platform Directory

Create the following file structure under `tech-radar-port/platforms/<platform-name>/`:

```
platforms/<platform-name>/
├── README.md          # Platform adaptation notes (install steps, configuration, known limitations)
├── agent.md           # Agent definition template (with {{INSTALL_DIR}} placeholder)
├── daily.sh           # Daily report scheduling script
├── weekly.sh          # Weekly report scheduling script
├── monthly.sh         # Monthly report scheduling script
└── [optional] extra components     # e.g., hooks, proxy scripts, systemd service, etc.
```

### Step 3: Write the Agent Definition

Based on the research results from Step 1, write `agent.md`. Start from `core/agent-prompt.md` (the platform-agnostic system prompt) and append the target platform's tool-mapping notes.

**Tool-mapping note template** (append after agent-prompt.md):

```markdown
## Tool Mapping Notes

This agent runs in the <platform-name> environment. The tool names are as follows:
- Search web content: <specific tool name> (<usage instructions>)
- Fetch web content: <specific tool name>
- Write file: <specific tool name> (<write method: full overwrite / create+append / patch>)
- Read file: <specific tool name>
- Run script: <specific tool name>
```

If the target platform requires hooks (such as Claude Code's shell-guard/write-guard), create them as well.

### Step 4: Write the Scheduling Scripts

Copy an existing supported platform's `daily.sh` as the base, then modify the following parts:

**4.1 CLI Invocation Command**

Find the `run_agent()` function and replace it with the target platform's CLI command.

**4.2 Prompt Template Path**

All scripts read templates from `$RADAR_HOME/core/daily.prompt.md` (or weekly/monthly), not from `$SCRIPT_DIR/`.

**4.3 Agent Prompt Assembly Strategy**

- If the platform auto-loads the system prompt from the agent definition file (e.g., Claude Code, OpenCode): the script passes only the task prompt
- If the platform requires passing the system prompt explicitly (e.g., Kiro-CLI): the script concatenates agent.md + the task prompt

**4.4 PATH Detection**

If the target platform's CLI was installed via nvm/pnpm/brew, add the corresponding PATH detection logic at the top of the script. The cron environment does not load the shell profile, so this must be set explicitly.

**4.5 Failure Detection**

Keep the `verify_output()` function (which checks whether the output file exists). Decide whether additional failure detection is needed based on the target platform's known behavior.

**4.6 INSTANCE_DIR Parameter**

`INSTANCE_DIR="$1"` (required; exit with an error if not provided).

### Step 5: Update instance.env.template

Add the target platform's model configuration example to `instance-template/instance.env.template`.

### Step 6: Write the Platform README

`platforms/<platform-name>/README.md` should include:

1. **Prerequisites**: what CLI, Python packages, and system dependencies need to be installed
2. **Install steps**: the complete flow for installing from `tech-radar-port` to this platform
3. **Model configuration**: how to configure the model on this platform (format, available values)
4. **Web search**: a description of this platform's search capability (natively available / requires configuration / requires a fallback plan)
5. **Known limitations**: limitations specific to this platform
6. **Manual testing**: how to manually run a daily report once for verification

### Step 7: End-to-end Testing

Execute in the following order; proceed to the next step only after the current one passes.

#### 7.1 Basic Connectivity Test

```bash
<platform-cli> --model <model> "What is 1+1?"
```

Expected: returns "2". If it fails: check the CLI installation, API key configuration, and network connectivity.

#### 7.2 Agent Definition Test

```bash
<platform-cli> --agent tech-radar --model <model> "Read the meta section of scan-config.yaml and output the instance name"
```

Expected: outputs the value of `meta.instance` in scan-config. If it fails: check the agent definition file path and format.

#### 7.3 Web Search Test

```bash
<platform-cli> --agent tech-radar --model <model> "Search for the latest sensor technology news and list 3 titles with sources"
```

Expected: returns 3 news titles with URLs, and the content is current. If the model returns stale news or fabricated content: websearch is unavailable; go back to Step 1.3 and re-evaluate.

#### 7.4 File Writing Test

```bash
<platform-cli> --agent tech-radar --model <model> "Write a test file containing 5 lines of content to /tmp/tech-radar-test.md"
```

Expected: the file is created with 5 lines of content. If it fails: check the write permission configuration.

#### 7.5 Python Script Test

```bash
<platform-cli> --agent tech-radar --model <model> "Run python3 -c \"import arxiv; print('arxiv ok')\""
```

Expected: outputs "arxiv ok". If it fails: `pip3 install arxiv`.

#### 7.6 Full Daily Report Test (Critical Verification)

```bash
bash platforms/<platform-name>/daily.sh <instance_dir>
```

After it completes, check:

| Check Item | Expected | How to Check |
|--------|------|----------|
| Daily .md file exists | Yes | `ls $REPORT_DIR/daily/$DATE.md` |
| items.yaml file exists | Yes | `ls $REPORT_DIR/daily/$DATE.items.yaml` |
| Frontmatter is complete | Yes | `head -20 $DATE.md` to check the YAML header |
| Domain coverage ≥7 | Yes | `grep "^## " $DATE.md \| wc -l` |
| Number of entries ≥10 | Yes | `grep "^### " $DATE.md \| wc -l` |
| Source citations have URLs | Yes | `grep "http" $DATE.md \| wc -l` ≥10 |
| items.yaml is parseable | Yes | `python3 -c "import yaml; yaml.safe_load(open('$DATE.items.yaml'))"` |
| arxiv papers ≥1 | Yes | frontmatter `arxiv_papers` field ≥1 |
| No fabricated content | Yes | manually spot-check 3 entries; confirm URLs are accessible |
| No shell file writes | Yes | no traces of echo/cat/tee redirections writing files in the log |

**If any item fails, proceed to Step 8 for troubleshooting. Once all pass, proceed to Step 7.7.**

#### 7.7 Cron Environment Test

```bash
# Simulate a minimal cron environment to run
env -i HOME=$HOME SHELL=/bin/sh PATH=/usr/bin:/bin \
    bash platforms/<platform-name>/daily.sh <instance_dir>
```

Expected: consistent with the results of 7.6. If it fails: it is usually a PATH issue (nvm not loaded); check the PATH detection logic at the top of the script.

### Step 8: Troubleshooting Guide

#### Problem 1: The model doesn't search and answers directly from training data

**Diagnosis**: no search tool invocation records in the log.

**Solution**:
- Check whether the agent permissions allow the search tool
- Check whether an environment variable is needed to enable search (e.g., OpenCode's `OPENCODE_ENABLE_EXA=1`)
- If the platform doesn't support websearch, instruct the model in the tool-mapping notes to use webfetch to access a search engine URL
- If the model supports native web_search but the platform doesn't pass it through, deploy an HTTP proxy to inject it

#### Problem 2: File Writing Fails

**Diagnosis**: the agent finishes running but no files appear in the output directory.

**Solution**:
- Check whether the agent permissions allow edit/write
- Check whether a write-guard hook is intercepting
- Check whether the tool mapping is correct (the model may have invoked a non-existent tool name)
- If the platform uses apply_patch instead of write, ensure the prompt mentions both are acceptable

#### Problem 3: arxiv Search Fails

**Symptom**: `arxiv_papers` is 0; the log shows `ModuleNotFoundError: No module named 'arxiv'`.

**Solution**: `pip3 install arxiv`.

#### Problem 4: Agent Not Found When Running via Cron

**Symptom**: manual run works fine, but cron reports "agent not found".

**Solution**:
- Confirm the PATH detection logic at the top of the script is correct
- Confirm the agent definition file is in the global location
- Explicitly `export HOME=$HOME` in the script

#### Problem 5: Timeout

**Solution**:
- Increase the timeout in `instance.env`
- Lower `budget.mode` from `unlimited` to `standard`
- Reduce the number of domains or keywords in scan-config

#### Problem 6: Weekly/Monthly Reports Cannot Read Daily Reports

**Solution**: confirm that the `REPORT_DIR` in `instance.env` is consistent across all scripts; confirm the items.yaml format is correct.

### Step 9: Update setup.sh

Add the target platform's install option to `setup.sh`.

### Completion Criteria

Porting is complete when all check items in Section 7.6 (Full Daily Report Test) pass, and cron runs automatically without errors for two consecutive days.

---
