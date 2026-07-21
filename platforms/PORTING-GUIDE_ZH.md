[English](PORTING-GUIDE.md)

---
# tech-radar 平台移植指南

本指南面向 AI agent。如果你是一个正在执行移植任务的 agent，请完整阅读本文件后按步骤执行。

## 移植目标

将 tech-radar 从已支持的平台（Claude Code / OpenCode / Kiro-CLI）移植到新的 AI 编码平台。
移植完成后，新平台应能通过 cron 定时调度，自动生成日报/周报/月报，且输出格式与现有平台一致。

## 移植边界

**需要移植的**（平台相关）：
- Agent 定义文件（frontmatter 格式、权限配置）
- CLI 调用脚本（daily.sh / weekly.sh / monthly.sh 中的 agent 调用命令）
- 工具映射（prompt 中的搜索/获取/写入/执行对应到目标平台的具体工具名）

**不需要移植的**（平台无关）：
- core/ 下的所有 prompt 模板（daily.prompt.md 等）
- core/agent-prompt.md（通用系统提示，不含具体工具名）
- instance-template/ 下的 scan-config 和 instance.env 模板
- skills/ 下的所有 skill 文件
- review-config.sh

## 移植流程

### 第 1 步：平台能力调研

在动手之前，先调研目标平台的以下能力。每项都要给出明确结论，不确定的必须实际测试。

#### 1.1 非交互式 CLI 调用

调研问题：
- 平台的 CLI 命令是什么？（如 `claude --print`、`opencode run`、`kiro-cli chat --no-interactive`）
- 如何指定 agent？（`--agent` 参数？配置文件？）
- 如何指定 model？（`--model` 参数？格式是别名还是 `provider/model-id`？）
- 如何自动批准权限？（`--auto`？`--dangerously-skip-permissions`？还是无此机制？）
- 输出是 stdout 还是需要特殊 flag？

验证方法：执行一个最简 prompt（如"1+1等于几"），确认能收到正确文本响应。

#### 1.2 Agent 定义机制

调研问题：
- Agent 定义文件放在哪里？（项目级 `.claude/agents/`？全局 `~/.config/opencode/agents/`？）
- 文件格式是什么？（Markdown + YAML frontmatter？JSON？）
- 必填字段有哪些？（name？description？mode？model？tools/permission？）
- 如何指定模型？（frontmatter 里写死？还是运行时 `--model` 覆盖？）
- 如何控制工具权限？（白名单？黑名单？权限规则对象？）

验证方法：创建一个最简 agent（description="test"），用 CLI 指定该 agent 运行，确认 agent 的 prompt 生效。

#### 1.3 网络搜索能力

这是移植中最关键的能力差异点。

调研问题：
- 平台是否内置 `websearch`（开放式搜索，不需要提供 URL）？
- 启用条件是什么？（默认可用？需要环境变量？需要配置搜索 provider？）
- 平台是否内置 `webfetch`（获取指定 URL 的网页内容）？
- 模型本身是否支持原生 web_search（如 GLM-5.2 的 `tools: [{"type":"web_search"}]`）？平台是否透传该参数？

验证方法：
- 测试 websearch：发送"今天北京天气"，看模型是否调用了搜索工具并返回实时信息
- 测试 webfetch：发送"获取 https://example.com 的内容"，看是否能读取网页
- 如果两者都不可用，记录降级方案（见第 1.6 节）

#### 1.4 文件写入能力

调研问题：
- 写入工具的名称和调用方式是什么？（`Write`？`write`？`apply_patch`？）
- 是全量覆盖还是支持 append？
- 是否有单次写入行数限制？
- 是否需要额外工具？（如 `apply_patch` 用于多文件补丁式编辑）

验证方法：用 agent 创建一个测试文件，写入 10 行内容，再读回来确认内容一致。

#### 1.5 Shell 命令执行

调研问题：
- Shell 工具的名称是什么？（`Bash`？`bash`？`shell`？）
- 是否有命令过滤/hook 机制？
- Python 脚本能否通过 shell 执行？

验证方法：通过 agent 执行 `python3 -c "print(1+1)"`，确认输出 "2"。

#### 1.6 降级方案评估（仅当 websearch/webfetch 不可用时）

如果目标平台不支持 websearch 或 webfetch，需要评估降级路径：

**方案 A：构造搜索 URL + webfetch**
如果平台有 webfetch 但没有 websearch，可以在 agent 的工具映射说明中指示模型用 webfetch 访问搜索引擎 URL：
- DuckDuckGo HTML：`https://html.duckduckgo.com/html/?q=QUERY&df=d`（df=d/w/m 控制时间范围）
- arXiv 搜索：`https://arxiv.org/search/?query=QUERY&searchtype=all&order=-announced_date_first`
- Google News RSS：`https://news.google.com/rss/search?q=QUERY&hl=en-US&gl=US&ceid=US:en`

**方案 B：curl + shell**
如果平台既没有 websearch 也没有 webfetch，但有 shell，可以用 curl。注意需要在 agent 的 shell 权限中允许 curl，且建议配置域名白名单。

**方案 C：模型原生 web_search**
如果模型本身支持原生 web_search（如 GLM-5.2、GPT-5.5），但平台的 provider 适配器不透传该参数，可以部署本地 HTTP 代理注入 `web_search` tool。参考 `platforms/opencode/glm-websearch-proxy.js`。

选择降级方案后，在平台适配的 agent.md 中追加工具映射说明，明确告知模型如何搜索和获取网页。

### 第 2 步：创建平台目录

在 `tech-radar-port/platforms/<platform-name>/` 下创建以下文件结构：

```
platforms/<platform-name>/
├── README.md          # 平台适配说明（安装步骤、配置方法、已知限制）
├── agent.md           # Agent 定义模板（含 {{INSTALL_DIR}} 占位符）
├── daily.sh           # 日报调度脚本
├── weekly.sh          # 周报调度脚本
├── monthly.sh         # 月报调度脚本
└── [可选] 额外组件     # 如 hooks、代理脚本、systemd service 等
```

### 第 3 步：编写 Agent 定义

基于第 1 步的调研结果，编写 `agent.md`。从 `core/agent-prompt.md`（平台无关的系统提示）开始，追加目标平台的工具映射说明。

**工具映射说明模板**（追加到 agent-prompt.md 之后）：

```markdown
## 工具映射说明

本 agent 运行在 <platform-name> 环境，工具名称如下：
- 搜索网络内容：<具体工具名>（<使用方式说明>）
- 获取网页内容：<具体工具名>
- 写文件：<具体工具名>（<写入方式：全量覆盖 / create+append / patch>）
- 读文件：<具体工具名>
- 运行脚本：<具体工具名>
```

如果目标平台需要 hooks（如 Claude Code 的 shell-guard/write-guard），一并创建。

### 第 4 步：编写调度脚本

从已支持平台的 `daily.sh` 复制为基础，修改以下部分：

**4.1 CLI 调用命令**

找到 `run_agent()` 函数，替换为目标平台的 CLI 命令。

**4.2 Prompt 模板路径**

所有脚本从 `$RADAR_HOME/core/daily.prompt.md`（或 weekly/monthly）读取模板，而非 `$SCRIPT_DIR/`。

**4.3 Agent prompt 拼接策略**

- 如果平台从 agent 定义文件自动加载系统提示（如 Claude Code、OpenCode）：脚本只传任务 prompt
- 如果平台需要显式传递系统提示（如 Kiro-CLI）：脚本拼接 agent.md + 任务 prompt

**4.4 PATH 探测**

如果目标平台的 CLI 通过 nvm/pnpm/brew 安装，在脚本开头添加对应的 PATH 探测逻辑。cron 环境不加载 shell profile，必须显式设置。

**4.5 失败检测**

保留 `verify_output()` 函数（检查输出文件是否存在）。根据目标平台的已知行为决定是否需要额外的失败检测。

**4.6 INSTANCE_DIR 参数**

`INSTANCE_DIR="$1"`（必填，不提供时报错退出）。

### 第 5 步：更新 instance.env.template

在 `instance-template/instance.env.template` 中添加目标平台的模型配置示例。

### 第 6 步：编写平台 README

`platforms/<platform-name>/README.md` 应包含：

1. **前置条件**：需要安装什么 CLI、Python 包、系统依赖
2. **安装步骤**：从 `tech-radar-port` 安装到本平台的完整流程
3. **模型配置**：该平台下如何配置模型（格式、可选值）
4. **网络搜索**：该平台的搜索能力说明（原生可用 / 需要配置 / 需要降级方案）
5. **已知限制**：该平台特有的限制
6. **手动测试**：如何手动运行一次日报验证

### 第 7 步：端到端测试

按以下顺序执行，每步通过后再进入下一步。

#### 7.1 基础连通性测试

```bash
<platform-cli> --model <model> "1+1等于几"
```

预期：返回 "2"。如果失败：检查 CLI 安装、API key 配置、网络连通性。

#### 7.2 Agent 定义测试

```bash
<platform-cli> --agent tech-radar --model <model> "读取 scan-config.yaml 的 meta 部分，输出 instance 名称"
```

预期：输出 scan-config 中 `meta.instance` 的值。如果失败：检查 agent 定义文件路径和格式。

#### 7.3 网络搜索测试

```bash
<platform-cli> --agent tech-radar --model <model> "搜索最新的传感器技术新闻，列出 3 条标题和来源"
```

预期：返回 3 条带有 URL 的新闻标题，且内容是实时的。如果模型返回旧闻或编造内容：websearch 不可用，回到第 1.3 步重新评估。

#### 7.4 文件写入测试

```bash
<platform-cli> --agent tech-radar --model <model> "在 /tmp/tech-radar-test.md 写入一个包含 5 行内容的测试文件"
```

预期：文件被创建，内容为 5 行。如果失败：检查写入权限配置。

#### 7.5 Python 脚本测试

```bash
<platform-cli> --agent tech-radar --model <model> "运行 python3 -c \"import arxiv; print('arxiv ok')\""
```

预期：输出 "arxiv ok"。如果失败：`pip3 install arxiv`。

#### 7.6 完整日报测试（关键验证）

```bash
bash platforms/<platform-name>/daily.sh <instance_dir>
```

等待完成后检查：

| 检查项 | 预期 | 检查方法 |
|--------|------|----------|
| 日报 .md 文件存在 | 是 | `ls $REPORT_DIR/daily/$DATE.md` |
| items.yaml 文件存在 | 是 | `ls $REPORT_DIR/daily/$DATE.items.yaml` |
| frontmatter 完整 | 是 | `head -20 $DATE.md` 检查 YAML 头 |
| 领域覆盖 ≥7 个 | 是 | `grep "^## " $DATE.md \| wc -l` |
| 条目数 ≥10 条 | 是 | `grep "^### " $DATE.md \| wc -l` |
| 来源引用有 URL | 是 | `grep "http" $DATE.md \| wc -l` ≥10 |
| items.yaml 可解析 | 是 | `python3 -c "import yaml; yaml.safe_load(open('$DATE.items.yaml'))"` |
| arxiv 论文 ≥1 篇 | 是 | frontmatter `arxiv_papers` 字段 ≥1 |
| 无编造内容 | 是 | 人工抽查 3 条，确认 URL 可访问 |
| 无 shell 写文件 | 是 | 日志中无 echo/cat/tee 重定向写文件的痕迹 |

**任何一项不通过，进入第 8 步排障。全部通过后进入第 7.7 步。**

#### 7.7 Cron 环境测试

```bash
# 模拟 cron 最小环境运行
env -i HOME=$HOME SHELL=/bin/sh PATH=/usr/bin:/bin \
    bash platforms/<platform-name>/daily.sh <instance_dir>
```

预期：与 7.6 结果一致。如果失败：通常是 PATH 问题（nvm 未加载），检查脚本开头的 PATH 探测逻辑。

### 第 8 步：排障指南

#### 问题 1：模型不搜索，直接用训练数据回答

**诊断**：日志中无搜索工具调用记录。

**解决**：
- 检查 agent 权限是否允许搜索工具
- 检查是否需要环境变量启用搜索（如 OpenCode 的 `OPENCODE_ENABLE_EXA=1`）
- 如果平台不支持 websearch，在工具映射说明中指示模型用 webfetch 访问搜索引擎 URL
- 如果模型支持原生 web_search 但平台不透传，部署 HTTP 代理注入

#### 问题 2：文件写入失败

**诊断**：agent 运行完成但输出目录无文件。

**解决**：
- 检查 agent 权限是否允许 edit/write
- 检查是否有 write-guard hook 拦截
- 检查工具映射是否正确（模型可能调用了不存在的工具名）
- 如果平台使用 apply_patch 而非 write，确保 prompt 中提到两者均可

#### 问题 3：arxiv 搜索失败

**症状**：`arxiv_papers` 为 0，日志出现 `ModuleNotFoundError: No module named 'arxiv'`。

**解决**：`pip3 install arxiv`。

#### 问题 4：Cron 运行时 agent 找不到

**症状**：手动运行正常，cron 报 "agent not found"。

**解决**：
- 确认脚本开头的 PATH 探测逻辑正确
- 确认 agent 定义文件在全局位置
- 在脚本中显式 `export HOME=$HOME`

#### 问题 5：超时

**解决**：
- 增加 `instance.env` 中的超时时间
- 降低 `budget.mode` 从 `unlimited` 到 `standard`
- 减少 scan-config 中的领域数量或关键词

#### 问题 6：周报/月报无法读取日报

**解决**：确认 `instance.env` 的 `REPORT_DIR` 在所有脚本中一致；确认 items.yaml 格式正确。

### 第 9 步：更新 setup.sh

在 `setup.sh` 中添加目标平台的安装选项。

### 完成标准

移植完成的标志是第 7.6 节（完整日报测试）的所有检查项全部通过，且连续两天 cron 自动运行无异常。

---
