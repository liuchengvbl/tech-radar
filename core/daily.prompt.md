请执行一次技术前沿日报搜集。

## 配置加载

读取配置文件 `${SCAN_CONFIG}` 获取：
- `meta`：实例信息、输出语言、时间窗口
- `budget.mode`：资源预算模式（决定搜索深度和输出篇幅）
- `domains`：搜集领域列表（含权重、关键词、关注实体）
- `sources`：固定信息源列表
- `signals`：当前信号追踪状态（trending/emerging/fading/declining）

## 工作流程

### 阶段 1：规划搜索策略

基于配置中的 domains，为每个领域规划搜索查询：
- `weight: high` 的领域：使用更多关键词组合，搜索更广泛
- `weight: medium` 的领域：使用核心关键词搜索
- `weight: low` 的领域：仅做基本扫描
- 如果 `watch_entities` 非空，为每个实体单独搜索最新动态
- 如果 `signals.trending` 非空，对趋势信号做针对性搜索
- 如果 `signals.emerging` 非空，对新兴信号做跟踪搜索
- 如果 `signals.fading` 非空，对衰退信号降低搜索优先级（仍扫描但不深入）
- 如果 `signals.declining` 非空，仅做最低限度扫描
- 搜索语言：英文和中文都要覆盖
- 时间范围：配置中的 `meta.time_window`
- **搜索时间限定**：所有搜索关键词中必须包含具体日期范围而非仅年份。例如今天是 ${DATE}，48h 窗口则搜索关键词应包含 "July 9-10 2026" 或 "2026年7月" 等具体时段，而不是仅写 "2026"

### 阶段 2：多源搜索与采集

使用多种手段并行采集，确保来源多样性。

**搜索量化下限**（确保每次运行的信息覆盖稳定）：
- `weight: high` 的领域：至少 3 组不同关键词搜索，每组取 top 5-8 条结果
- `weight: medium` 的领域：至少 2 组关键词搜索，每组取 top 3-5 条结果
- `weight: low` 的领域：至少 1 组关键词搜索，取 top 3 条结果
- 每次运行总候选条目不少于 40 条（筛选前）

**2a. Web 搜索**（主力）
对每个领域执行关键词搜索，搜索结果会自动附带引用来源。
使用 scan-config 中的 keywords 以及 agent 自行扩展的关键词组合。
英文搜索和中文搜索分别执行，确保双语覆盖。

**2b. 学术预印本**
使用 Python `arxiv` 库搜索相关学术论文（已安装，直接 `import arxiv` 即可）。

**arXiv API 限速应对**：arXiv API 频繁返回 HTTP 429。必须在每次 API 调用之间加 `time.sleep(5)` 延迟。如果仍然 429，降级为通过网页搜索访问 arXiv 搜索页面 `https://arxiv.org/search/?query=QUERY&searchtype=all&order=-announced_date_first`，不要反复重试 API。

示例用法：
```python
import arxiv, time
client = arxiv.Client()
queries = ["novel biosensor", "MEMS inertial sensor"]
for q in queries:
    search = arxiv.Search(query=q, max_results=10, sort_by=arxiv.SortCriterion.SubmittedDate)
    for r in client.results(search):
        print(r.published.date(), r.title, r.entry_id)
    time.sleep(5)  # 必须：避免 429 限速
```
重点类别：
- `eess.SP`（信号处理）、`cs.HC`（人机交互）、`physics.app-ph`（应用物理）
- `cs.CV`（计算机视觉，与传感相关的）、`q-bio.QM`（定量生物学方法）
可通过 query 中加 `cat:eess.SP` 限定类别。
每个 high 权重领域至少搜索一次 arXiv。

**论文阅读策略**（严格遵守，控制耗时）：
1. **浏览阶段**（不限篇数）：只读每篇论文的标题、作者、单位、摘要（arxiv.Search 返回的 summary 字段）。不要访问论文全文 PDF。
2. **推荐打分**：对每篇浏览过的论文打 1-5 分（5=强烈推荐精读），评分依据：
   - 与本实例搜集领域的相关度
   - 技术新颖性（是否提出新方法/新材料/新架构）
   - 潜在产业影响（是否可能改变现有技术路线）
   - 文献综述（review/survey）类论文加 1 分（综述信息密度高）
3. **精读阶段**：按打分从高到低，选取最多 `budget.paper.daily_deep_read` 篇论文访问全文详细内容。
4. 在日报中，浏览过的论文列出标题+摘要要点+推荐分数；精读过的论文展开详细分析。

**2c. 固定信息源巡检**
对配置中 `sources` 列表的每个信息源，获取其最新内容。
这是保证基线覆盖的关键——即使 web 搜索结果有随机性，固定信源提供稳定的信息来源。

**2d. 边缘来源扫描**（弱信号检测）
参考 environmental-scanning-foresight 的弱信号检测方法，额外关注：
- 初创公司动态：新融资、新产品发布（VC funding, accelerator cohorts）
- 专利动向：关键实体的新专利申请
- 跨领域交叉：其他领域（AI、材料科学、生物技术）中可能影响本领域的突破

### 阶段 3：筛选与去重

对采集到的候选条目进行筛选：
- **时效性过滤**（最重要，优先于其他筛选）：
  - 区分"文章发布时间"和"事件发生时间"。文章新 ≠ 事件新。
  - **事件发生时间**在 `meta.time_window`（48h）内的 → 保留
  - 文章发布时间在 48h 内，但描述的核心事件（产品发布、论文发表、融资完成等）发生在更早之前 → **仅当文章包含该事件的实质性新信息**（新数据、新进展、后续影响）时保留，否则过滤
  - 典型应过滤的例子：回顾/盘点类文章、对已发布产品的常规评测、旧新闻的转载聚合
  - 如果无法确定事件时间，根据文章内容判断：提到"近日""本周""刚刚"等时效词的保留，提到"今年早些时候""年初""去年"等的过滤
  - **硬性上限**：事件发生在 2 周以前的旧来源，即使包含新信息，也必须在条目标题前标注 `[旧闻补充]`，且此类条目总数不得超过报告总条目的 20%。超出时优先删除信号强度最低的旧条目
- **去重**：同一事件的不同来源只保留信息最丰富的一条，但记录其他来源 URL 作为交叉验证
- **相关性过滤**：去除与领域无关的条目
- **优先级排序**（借鉴 Agently 的 relevance_score 机制）：
  - 有具体数据/参数/指标的 → 高优先
  - 来自 high quality 信息源的 → 高优先
  - 涉及 watch_entities 的 → 高优先
  - 涉及 signals.trending 或 signals.emerging 的 → 高优先
  - 涉及 signals.fading 的 → 正常优先（仍保留，但不额外加权）
  - 涉及 signals.declining 的 → 低优先（除非有复苏迹象）
  - 来自边缘来源但可能是弱信号的 → 标记为"待验证信号"

### 阶段 4：深度阅读与摘要

对筛选后的条目，访问原文获取详细信息，撰写结构化摘要。

每个条目的输出结构：
- **标题**：简洁概括
- **正文**：核心事实、技术细节、关键数据指标
- **"为什么重要"**（借鉴 Agently 的 recommend_comment）：一句话说明该条目的意义或潜在影响
- **来源标注**：行内 [N] 编号引用；如有交叉验证来源，标注"另见 [M]"
- **信号标签**：该条目涉及的技术关键词（用于后续趋势统计）

budget.mode 对输出的影响：
- `unlimited`：充分展开技术细节和背景分析，不限篇幅
- `standard`：每条目 1-2 段，聚焦核心事实
- `economy`：每条目 1-2 句，仅保留关键信息

### 阶段 5：组装报告

将所有条目按领域组织成完整报告。每个领域章节开头用 2-3 句话概括本领域当日态势（借鉴 Agently write_column 的 prologue 设计）。

### 阶段 6：信号标注

在报告末尾附"趋势信号"章节：
- 对照配置中的 `signals`，标注每个信号的状态变化（持续/增强/减弱/新增/消失）
- 识别本次扫描中新出现的、不在现有 signals 列表中的潜在信号
- 对弱信号进行初步验证（参考 environmental-scanning-foresight 的验证框架）：
  - 来源可信度（高/中/低）
  - 是否有独立来源交叉验证
  - 如果放大，潜在影响有多大
- 为每个信号给出信号强度评级（★ 到 ★★★★★）

### 阶段 7：信息源评估（附在报告末尾）

对本次搜集过程中的信息源做简要评估：
- 哪些固定信息源本次提供了有价值的内容
- 是否发现了新的高质量信息源（建议添加到 scan-config，如有可能用 rss-agent-discovery 探测其 RSS feed）
- 哪些固定信息源本次未能提供有效内容（可能需要更新 URL 或降级）

## 输出

### ⚠️ 写入策略（必须严格遵守）

文件写入工具是全量覆盖写入，支持单次写入完整文件内容。

写入方式：
1. **Markdown 日报**：组装完整内容后，使用文件写入工具写入整个文件
2. **items.yaml**：组装完整内容后，使用文件写入工具写入整个文件

**禁止**：
- 禁止用 shell 命令（echo/cat/tee/heredoc 重定向）写文件

### 文件 1：Markdown 日报（source of truth）

写入路径：`${REPORT_DIR}/daily/${DATE}.md`

格式要求：
- 文件开头 YAML frontmatter：
```
---
date: ${DATE}
type: daily-radar
instance: tech-radar
domains: [按实际搜集的领域列出]
tags: [本日报涉及的技术关键词标签，10-20 个]
source_count: N
item_count: N
budget_mode: ${BUDGET_MODE}
arxiv_papers: N
weak_signals: [本次识别的弱信号关键词]
---
```
- 标题：`# 技术前沿日报 ${DATE}`
- 按 domains 配置中的领域顺序分章节，每章节开头有态势概括
- 如果某领域当日无新动态，简要说明，不要编造
- 正文中每条事实后紧跟 [N] 编号引用
- 末尾"趋势信号"章节
- 末尾"信息源评估"章节
- 末尾"参考来源"章节，按编号列出完整引用：[N] 来源名称, "标题", 日期. URL


### 文件 2：结构化条目数据（供周报/月报聚合用）

写入路径：`${REPORT_DIR}/daily/${DATE}.items.yaml`

每个条目一条记录，格式：
```yaml
items:
  - title: "条目标题"
    domain: "所属领域名称"
    tags: [tag1, tag2]
    source_type: academic | industry | funding | patent | product | market
    source_quality: high | medium | low
    source_url: "https://..."  # 必须是具体文章的完整 URL，不是域名
    weak_signal: false
    watch_entity: ""  # 如涉及 watch_entities 中的实体则填写
```

这个文件是机器可读的结构化数据，用于下游周报/月报的自动化聚合统计。不需要人阅读。

## 约束

- 不要使用 ~/Documents/ 或其他目录
- 不要创建子文件夹
- 信息必须来自可验证的公开来源，禁止编造
- 搜索范围要广：英文和中文来源都要覆盖
- 如果 arXiv 搜索脚本不可用，跳过学术预印本搜索，不要因此中断整个流程
