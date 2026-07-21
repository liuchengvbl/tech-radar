[中文](DESIGN-DECISIONS_ZH.md)

# Design Decisions & Lessons Learned

This document records the key architectural decisions and pitfalls encountered during the development of tech-radar, for reference during future porting, extension, and debugging.

## Architectural Decisions

### Why use the Heartbeat Pattern (stateless cron agent) instead of a resident process?

The agent runs statelessly, awakened by cron scheduling, reads configuration and historical data from external files, completes its task, writes the results, and exits.

**Decision basis**:
- AI agents have a limited context window; a resident process accumulates garbage context after multiple rounds of conversation, leading to quality degradation
- The stateless design naturally supports retries—on failure, simply re-run without needing to restore state
- cron is the most reliable timed scheduling mechanism and requires no additional daemon

### Why use the Intelligence Cycle methodology?

Four-stage flow: Daily Scanning → Periodic Synthesis → Deep Analysis → Feedback Loop.

**Decision basis**:
- The intelligence cycle is a mature methodology with a well-established academic and practical foundation
- The four-stage temporal rhythm (day→week→month→feedback) matches the information decay pattern
- Human-in-the-Loop is only present in the monthly report stage—the Hype Cycle judgments and configuration proposals in the monthly report require human review

### Why use the TEM four-quadrant model instead of a tripartite classification?

The Topic Emergence Map classifies signals into trending/emerging/fading/declining based on two dimensions (heat × trend direction).

**Decision basis**: Referencing the WISDOM framework, the tripartite classification (hot/emerging/declining) cannot distinguish between "once hot but cooling down" and "low attention and still declining."

### Why doesn't the monthly report automatically update scan-config?

The monthly report generates a `config-proposal.yaml` (a proposal file) that requires manual review and merging by a human.

**Decision basis**: AI's trend judgments have errors; decisions such as domain weight adjustments, keyword additions/removals, and source promotion/demotion affect all subsequent daily reports—once wrong, the error is continuously amplified. Human review is a necessary feedback-loop control.

### Why do the daily/weekly/monthly reports use different models?

The daily report uses a fast model (collection and organization), while the weekly/monthly reports use a strong model (deep analysis).

**Decision basis**: The core of the daily report is broad search + structured organization, which does not require strong reasoning; the weekly/monthly reports require quantitative analysis, correlational reasoning, and Hype Cycle judgments, which require strong reasoning capability. Models are configured via `instance.env`, and scripts pass them in via the `--model` parameter.

### Why was the external popularity query removed?

The weekly report previously had a "Stage 1.5: External Popularity Query" that used pytrends (an unofficial Google Trends scraper) and the Semantic Scholar API to query the external popularity of the top 15 tags as a supplementary metric.

**Reasons for removal**:
- **pytrends unmaintained**: Version 4.9.2 used the `method_whitelist` parameter, but urllib3 2.x removed this parameter (replaced by `allowed_methods`), rendering the library unusable. The pytrends repository was archived in April 2025 and is no longer maintained.
- **pytrends 429 rate limiting is the norm**: Google Trends has no public API; pytrends essentially simulates browser scraping and is rate-limited by IP, easily triggering 429 during batch queries.
- **Semantic Scholar API 429 rate limiting**: Unauthenticated requests are limited to at most 10 per 5 seconds, frequently triggering rate limits when batch-querying paper citation counts.
- **Agent going down a rabbit hole**: The direct cause of the W29 weekly report failure—after encountering the pytrends compatibility error, the agent repeatedly tried to fix the source code instead of skipping it, and all 5 of the 40-minute timeouts got stuck here. The "skip if failed" instruction in the prompt was not forceful enough.
- **Core data unaffected**: The core data of the weekly report comes from the tag frequency and topic share statistics of the daily reports; external popularity is only a supplementary metric. The W28 weekly report maintained good quality after skipping external popularity.

**Porter's guide**: If you have a usable external popularity data source (such as the official Google Trends API (2025 Alpha, requires application), Baidu Index API, or other stable popularity services), you can insert a "Stage 1.5: External Popularity Query" step between Stage 1 and Stage 2 of the weekly report prompt, appending the query results to the tag popularity table. It is recommended to explicitly set a "skip on query failure, no retry" strategy in the prompt to prevent the agent from spending too much time fixing external API issues.

## Prompt Design Experience

### Search quantity lower bounds

Early daily reports had unstable information volume and high randomness. Solution: set hard lower bounds in the prompt—high-weight domains require at least 3 search groups, medium at least 2, low at least 1, with no fewer than 40 total candidates.

### Fixed sources as baseline coverage

web_search results have randomness; fixed sources provide a stable information source. The prompt requires inspecting each source in scan-config.

### Two-level paper reading strategy

**Pitfall**: Early agents read the full text of 30 arXiv papers, causing a 30-minute timeout.

**Solution**: Browsing stage (read only title + abstract, no limit on count) → recommendation scoring (1-5 points, +1 for survey papers) → intensive reading stage (sorted by score from high to low, at most N papers, where N is configured in `scan-config`'s `budget.paper`).

### Timeliness filtering takes priority over deduplication

A new article ≠ a new event. The prompt explicitly requires distinguishing between "article publication time" and "event occurrence time"; old sources where the event occurred more than 2 weeks ago are labeled `[旧闻补充]` (supplementary old news) and must not exceed 20% of total entries.

## Engineering Pitfalls

### Differences between cron environment and interactive environment

| Problem | Cause | Solution |
|------|------|------|
| cron cannot find the CLI | PATH does not include nvm/pnpm install paths | Manually probe nvm and export PATH at the start of the script |
| agent definition not found | agent file is in a project-level directory instead of global | Place it in a global location (e.g., `~/.config/opencode/agents/`) |
| environment variables missing | cron does not load shell profile | Explicitly `export HOME=$HOME` in the script |

The script includes environment logging (PATH/HOME/SHELL/CLI paths), output to `$DATE.env.log`, for comparing differences between cron and manual environments.

### `set -e` conflict with timeout

`set -euo pipefail` caused the script to exit silently without writing logs when `timeout` returned a non-zero exit. Changed to `set -uo pipefail` (removed `-e`), manually checking the exit codes of critical steps.

### CLI returns exit=0 but no output

Some platforms (such as kiro-cli) return exit=0 after an API dispatch timeout but do not generate an output file. Solution: `verify_output()` checks whether the output file exists rather than relying on the exit code. Added `is_dispatch_failure()` to detect the "dispatch failure" string in the logs.

### budget extraction false match

`grep 'mode:'` matched comment lines. Changed to `python3 -c "import yaml; ..."` using a YAML parser to extract, completely avoiding false matches.

### web_search tool unavailable

**Symptom**: The agent used shell to call curl/python scripts for searching, which was extremely inefficient and frequently timed out.

**Root cause**: The platform did not enable websearch, or the provider adapter did not pass through the model's native web_search parameters.

**Solution**: See [platforms/PORTING-GUIDE.md](platforms/PORTING-GUIDE.md) Section 1.3 and Section 1.6 for the fallback scheme evaluation.

### Write-file infinite loop

**Symptom**: The agent tried to write a 34K daily report via shell; the LLM-generated tool call JSON was missing required fields, the platform validation rejected it, and the LLM repeatedly retried the same format—191 failures until timeout.

**Root cause**: The prompt did not explicitly prohibit writing files via shell, and the model chose a write method it was not good at.

**Solution**: Explicitly state in the prompt "Use the file-write tool for writing files; writing files via shell's echo/cat/tee/heredoc redirection is prohibited."

### Hook exit code semantics

In some platforms' hook systems, exit 1 only warns without blocking execution; exit 2 is what truly intercepts. When debugging a hook that doesn't take effect, check the exit code first.

### write path whitelist may fail in non-interactive mode

On some platforms (such as kiro-cli `--no-interactive` mode), the `allowedPaths` configuration does not take effect, and write can write to any path. A hook is needed to implement path filtering as a supplement.

## Methodology References

| Methodology | Source | Used in |
|--------|------|------|
| Intelligence Cycle (情报循环) | Classical intelligence studies | Overall architecture |
| Heartbeat Pattern | Industry agent automation practice | Scheduling architecture |
| TEM four-quadrant model (TEM 四象限模型) | WISDOM framework | Weekly report signal classification |
| Hype Cycle | Gartner | Monthly report technology maturity assessment |
| TRL | NASA | Monthly report technology readiness assessment |
| Five-dimensional momentum scoring (五维动量评分) | McKinsey Technology Trends Outlook | Monthly report trend quantification |
| Cross-impact Analysis | Environmental scanning foresight methodology | Weekly/monthly report correlation analysis |
| Weak signal detection (弱信号检测) | Environmental Scanning Foresight | Daily report edge scanning |
