---
name: intelligence-radar
description: 技术前沿情报自动搜集与分析系统的维护技能。覆盖日报/周报/月报的四环情报循环（Daily Scanning → Periodic Synthesis → Deep Analysis → Feedback Loop），基于 Heartbeat Pattern 的 cron 调度架构，scan-config 配置管理，报告输出。当用户提到情报搜集系统的配置、调试、新增实例、修改领域、查看运行状态、排查问题时使用。
---

# Intelligence Radar — 系统维护技能

## 系统概述

基于情报循环（Intelligence Cycle）方法论的自动化技术前沿搜集与分析系统。采用 Heartbeat Pattern 架构：agent 无状态运行，按 cron 调度唤醒，从外部文件读取配置和历史数据，完成任务后写入结果并退出。

## 架构

```
cron 调度 → kiro-cli chat --agent --no-interactive → prompt 模板 + scan-config → 报告输出到指定目录
```

### 四环流转

| 环节 | 频率 | 脚本 | prompt | 产出 | 自动/人审 |
|------|------|------|--------|------|----------|
| Daily Scanning | 每天 6:00 | daily.sh | daily.prompt.md | {DATE}.md + {DATE}.items.yaml | 全自动 |
| Periodic Synthesis | 每周日 8:00 | weekly.sh | weekly.prompt.md | weekly/{WEEK_ID}.md + 更新 signals | 全自动 |
| Deep Analysis | 每月1日 8:00 | monthly.sh | monthly.prompt.md | monthly/{MONTH}.md + {MONTH}-config-proposal.yaml | AI 生成草稿，人审 |
| Feedback Loop | 人工触发 | review-config.sh | 无 | 更新 scan-config.yaml | 人工 |

### 文件结构

```
~/agent_automation/{instance}/       ← 运维目录
├── scripts/
│   ├── instance.env                 ← 实例配置（路径、agent 名）
│   ├── scan-config.yaml             ← 核心搜集配置（领域/信源/信号）
│   ├── daily.prompt.md              ← 日报 prompt 模板
│   ├── daily.sh                     ← 日报调度脚本
│   ├── weekly.prompt.md             ← 周报 prompt 模板
│   ├── weekly.sh                    ← 周报调度脚本
│   ├── monthly.prompt.md            ← 月报 prompt 模板
│   ├── monthly.sh                   ← 月报调度脚本
│   └── review-config.sh             ← 人审辅助脚本
└── logs/                            ← 运行日志
    ├── cron.log                     ← 每日运行状态摘要
    ├── {DATE}.log                   ← 日报详细日志
    ├── weekly-{WEEK_ID}.log
    └── monthly-{MONTH}.log

~/Disk1/tech-radar/{instance}/   ← 报告输出
├── README.md                        ← 索引页
├── {DATE}.md                        ← 日报
├── {DATE}.items.yaml                ← 日报结构化数据
├── weekly/
│   └── {WEEK_ID}.md                 ← 周报
└── monthly/
    ├── {MONTH}.md                   ← 月报
    └── {MONTH}-config-proposal.yaml ← 配置修改建议
```

### 数据流

```
scan-config.yaml ──→ daily.prompt ──→ 日报(.md + .items.yaml)
                                          ↓
                                     weekly.prompt ──→ 周报(.md) ──→ 更新 signals
                                          ↓
                                     monthly.prompt ──→ 月报(.md) + config-proposal
                                          ↓
                                     人审 ──→ 更新 scan-config.yaml ──→ 闭环
```

### 信号四象限模型（Topic Emergence Map）

| 象限 | 热度 | 趋势 | 分类 |
|------|------|------|------|
| 右上 | 高 | ↑ | trending（强信号） |
| 左上 | 低 | ↑ | emerging（弱信号） |
| 右下 | 高 | ↓ | fading（衰退信号） |
| 左下 | 低 | ↓ | declining（潜伏信号） |

### 月报技术成熟度评估

- **五维动量评分**（McKinsey 方法论）：学术/媒体/投资/产品/专利
- **Hype Cycle 五阶段**：触发→膨胀→幻灭→爬坡→成熟
- **TRL 1-9**：辅助评估技术就绪度

### 依赖的 skills

| Skill | 用途 | 用在哪个环节 |
|-------|------|------------|
| deep-research | 多源搜索 + 报告生成 | 日报 |
| arxiv-search | 学术预印本搜索 | 日报 |
| rss-agent-discovery | 发现 RSS feed | 日报信息源评估 |
| environmental-scanning-foresight | 弱信号检测、交叉影响分析 | 周报、月报 |

### Agent 配置

agent 名称：`tech-radar`（通用名，可用于任何领域实例）
配置位置：`~/.kiro/agents/tech-radar.json`

模型配置（`instance.env`）：
- 日报：`glm-5`（5/4 从 claude-sonnet-4.6 切换，规避 dispatch failure）
- 周报/月报：`claude-opus-4.6`

## 常见维护操作

### 查看运行状态
```bash
cat ~/agent_automation/{instance}/logs/cron.log
```

### 手动补跑
```bash
~/agent_automation/{instance}/scripts/daily.sh
~/agent_automation/{instance}/scripts/weekly.sh
~/agent_automation/{instance}/scripts/monthly.sh
```

### 修改搜集领域
编辑 `~/agent_automation/{instance}/scripts/scan-config.yaml` 的 `domains` 区域。

### 审阅月报配置建议
```bash
~/agent_automation/{instance}/scripts/review-config.sh {MONTH}
```

### 新建实例
1. 复制 `~/agent_automation/tech-radar/` 为新目录
2. 编辑 `scripts/instance.env`（改 INSTANCE_NAME、REPORT_DIR）
3. 编辑 `scripts/scan-config.yaml`（改 meta、domains、sources）
4. 创建报告输出目录
5. 添加 3 条 cron（daily/weekly/monthly）

### 迁移到其他机器
核心资产（prompt 模板、scan-config、报告）全部是纯文本文件，可直接复制。
需要适配的：
- `instance.env` 中的路径
- cron 配置
- kiro-cli 安装和 agent 注册
