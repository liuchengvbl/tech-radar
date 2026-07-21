# 设计决策与经验教训

本文档记录 tech-radar 开发过程中的关键架构决策和踩过的坑，供后续移植、扩展、调试时参考。

## 架构决策

### 为什么用 Heartbeat Pattern（无状态 cron agent）而非常驻进程？

agent 无状态运行，按 cron 调度唤醒，从外部文件读取配置和历史数据，完成任务后写入结果并退出。

**决策依据**：
- AI agent 的上下文窗口有限，常驻进程会在多轮对话后积累垃圾上下文，导致质量下降
- 无状态设计天然支持重试——失败后重新运行即可，无需恢复状态
- cron 是最可靠的定时调度机制，不需要额外守护进程

### 为什么用 Intelligence Cycle（情报循环）方法论？

四环流转：Daily Scanning → Periodic Synthesis → Deep Analysis → Feedback Loop。

**决策依据**：
- 情报循环是成熟的方法论，有完善的学术和实践基础
- 四环的时间节奏（日→周→月→反馈）与信息衰减规律匹配
- 人在环（Human-in-the-Loop）只在月报环节——月报的 Hype Cycle 判定和配置建议需要人审

### 为什么用 TEM 四象限模型而非三分法？

Topic Emergence Map 基于两个维度（热度 × 趋势方向）将信号分为 trending/emerging/fading/declining。

**决策依据**：参考 WISDOM 框架，三分法（热门/新兴/衰退）无法区分"曾经热门但正在降温"和"低关注度且仍在下降"。

### 为什么月报不自动更新 scan-config？

月报生成 `config-proposal.yaml`（建议文件），需要人审后手动合并。

**决策依据**：AI 的趋势判断有误差，领域权重调整、关键词增删、信源升降级等决策影响后续所有日报，一旦错误会持续放大。人审是必要的反馈环控制。

### 为什么日报/周报/月报用不同模型？

日报用快模型（搜集整理），周报/月报用强模型（深度分析）。

**决策依据**：日报的核心是广度搜索+结构化整理，不需要强推理；周报/月报需要量化分析、关联推理、Hype Cycle 判定，需要强推理能力。模型通过 `instance.env` 配置，脚本用 `--model` 参数传入。

### 为什么移除外部热度查询？

周报原有一个"阶段 1.5：外部热度查询"，使用 pytrends (Google Trends 非官方爬虫) 和 Semantic Scholar API 查询 top 15 tags 的外部热度作为补充指标。

**移除原因**：
- **pytrends 停更**：4.9.2 版本使用了 `method_whitelist` 参数，但 urllib3 2.x 已移除该参数（改为 `allowed_methods`），导致库无法使用。pytrends 仓库已于 2025 年 4 月归档，不再维护。
- **pytrends 429 限流是常态**：Google Trends 没有公开 API，pytrends 本质是模拟浏览器爬取，按 IP 限流，批量查询时极易触发 429。
- **Semantic Scholar API 429 限流**：未认证请求限制为每 5 秒最多 10 次，批量查询论文引用数时频繁触发限流。
- **agent 钻牛角尖**：W29 周报失败的直接原因——agent 遇到 pytrends 兼容性报错后，反复尝试修复源码而非跳过，5 次 40 分钟超时全部卡在这里。prompt 中的"如果失败则跳过"指令不够强硬。
- **核心数据不受影响**：周报的核心数据来自日报的 tag 频率和 topic share 统计，外部热度只是补充指标。W28 周报跳过外部热度后质量依然良好。

**移植者指南**：如果你有可用的外部热度数据源（如 Google Trends 官方 API（2025 Alpha，需申请）、百度指数 API、或其他稳定的热度服务），可在周报 prompt 的阶段 1 和阶段 2 之间插入"阶段 1.5：外部热度查询"步骤，查询结果附加到 tag 热度表中。建议在 prompt 中明确设定"查询失败则跳过，不重试"的策略，避免 agent 花费过多时间在修复外部 API 问题上。

## Prompt 设计经验

### 搜索量化下限

早期日报信息量不稳定、随机性大。解决方案：在 prompt 中设定硬性下限——high 权重领域至少 3 组搜索、medium 至少 2 组、low 至少 1 组，总候选不少于 40 条。

### 固定信源作为基线覆盖

web_search 结果有随机性，固定信源提供稳定的信息来源。prompt 中要求对 scan-config 的每个 source 执行巡检。

### 论文阅读两级策略

**踩坑**：早期 agent 精读了 30 篇 arXiv 论文全文，导致 30 分钟超时。

**解决**：浏览阶段（只读标题+摘要，不限篇数）→ 推荐打分（1-5 分，综述类加 1 分）→ 精读阶段（按分数从高到低，最多 N 篇，N 在 `scan-config` 的 `budget.paper` 配置）。

### 时效性过滤优先于去重

文章新 ≠ 事件新。prompt 中明确要求区分"文章发布时间"和"事件发生时间"，事件发生在 2 周以前的旧来源标注 `[旧闻补充]` 且不超过总条目 20%。

## 工程踩坑

### cron 环境与交互式环境差异

| 问题 | 原因 | 解决 |
|------|------|------|
| cron 找不到 CLI | PATH 不含 nvm/pnpm 安装路径 | 脚本开头手动探测 nvm 并 export PATH |
| agent 定义找不到 | agent 文件在项目级目录而非全局 | 放到全局位置（如 `~/.config/opencode/agents/`） |
| 环境变量缺失 | cron 不加载 shell profile | 脚本中显式 `export HOME=$HOME` |

脚本中加入环境日志（PATH/HOME/SHELL/CLI 路径），输出到 `$DATE.env.log`，用于对比 cron 与手动环境差异。

### `set -e` 与 timeout 冲突

`set -euo pipefail` 导致 `timeout` 非零退出时脚本静默退出不写日志。改为 `set -uo pipefail`（去掉 `-e`），手动检查关键步骤退出码。

### CLI 返回 exit=0 但无输出

部分平台（如 kiro-cli）在 API dispatch timeout 后返回 exit=0 但未生成输出文件。解决方案：`verify_output()` 检查输出文件是否存在，而非依赖退出码。增加 `is_dispatch_failure()` 检测日志中的 "dispatch failure" 字符串。

### budget 提取误匹配

`grep 'mode:'` 匹配到了注释行。改为 `python3 -c "import yaml; ..."` 用 YAML 解析器提取，彻底避免误匹配。

### web_search 工具不可用

**症状**：agent 用 shell 调 curl/python 脚本搜索，效率极低，频繁超时。

**根因**：平台未启用 websearch，或 provider 适配器不透传模型原生 web_search 参数。

**解决**：参见 [platforms/PORTING-GUIDE.md](platforms/PORTING-GUIDE.md) 第 1.3 节和第 1.6 节的降级方案评估。

### 写文件死循环

**症状**：agent 尝试用 shell 写 34K 日报，LLM 生成的 tool call JSON 缺少必要字段，平台校验拒绝，LLM 反复重试同样格式，191 次失败直到超时。

**根因**：prompt 未明确禁止用 shell 写文件，模型选择了不擅长的写入方式。

**解决**：prompt 中明确"写文件使用文件写入工具，禁止用 shell 的 echo/cat/tee/heredoc 重定向写文件"。

### Hook exit code 语义

部分平台的 hook 系统中，exit 1 只警告不阻止执行，exit 2 才真正拦截。调试 hook 不生效时先检查 exit code。

### write 路径白名单可能在非交互模式下失效

某些平台（如 kiro-cli `--no-interactive` 模式）的 `allowedPaths` 配置不生效，write 可以写任何路径。需要用 hook 实现路径过滤作为补充。

## 方法论参考来源

| 方法论 | 来源 | 用在 |
|--------|------|------|
| Intelligence Cycle | 经典情报学 | 整体架构 |
| Heartbeat Pattern | 业界 Agent 自动化实践 | 调度架构 |
| TEM 四象限模型 | WISDOM 框架 | 周报信号分类 |
| Hype Cycle | Gartner | 月报技术成熟度判定 |
| TRL | NASA | 月报技术就绪度评估 |
| 五维动量评分 | McKinsey Technology Trends Outlook | 月报趋势量化 |
| Cross-impact Analysis | 环境扫描前瞻方法论 | 周报/月报关联分析 |
| 弱信号检测 | Environmental Scanning Foresight | 日报边缘扫描 |
