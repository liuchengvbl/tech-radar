[English](README.md)

# tech-radar — 技术前沿情报 Agent

自动化技术情报搜集系统。通过 cron 定时调度 AI agent，扫描指定领域的最新动态，生成结构化日报/周报/月报。

支持多平台（Claude Code / OpenCode / Kiro-CLI），同一套 prompt 和配置可跨平台运行。

## 功能

- **日报**：每日自动扫描多个技术领域，生成带引用来源的 Markdown 报告
- **周报**：汇总一周日报，绘制信号趋势图（TEM 四象限模型）
- **月报**：深度趋势分析，含 Hype Cycle 阶段判定、TRL 评估、配置修改建议
- **多实例**：同一套脚本可驱动多个不同领域的实例（如 sensor、robotics、biotech）

## 目录结构

```
tech-radar-port/
├── core/                           # 平台无关的核心资产
│   ├── agent-prompt.md             #   通用 agent 系统提示（不含具体工具名）
│   ├── daily.prompt.md             #   日报 prompt 模板
│   ├── weekly.prompt.md            #   周报 prompt 模板
│   ├── monthly.prompt.md           #   月报 prompt 模板
│   ├── review-config.sh            #   月度配置审核辅助脚本
│   ├── SKILL.md                    #   系统维护技能文档
│   └── skills/                     #   打包的 skill 文件
│       ├── arxiv-search/
│       ├── deep-research/
│       ├── environmental-scanning-foresight/
│       ├── evaluating-new-technology/
│       └── rss-agent-discovery/
│
├── instance-template/
│   ├── instance.env.template       #   实例配置模板（路径、模型、超时）
│   └── scan-config.example.yaml    #   搜集领域配置示例
│
├── platforms/                      # 平台适配层
│   ├── PORTING-GUIDE.md            #   移植到新平台的完整指南（面向 AI agent）
│   ├── claude-code/                #   Claude Code 适配
│   │   ├── agent.md                #     Agent 定义（frontmatter + 工具映射）
│   │   ├── daily.sh / weekly.sh / monthly.sh
│   │   ├── hooks/                  #     shell-guard + write-guard
│   │   └── README.md
│   ├── opencode/                   #   OpenCode 适配
│   │   ├── agent.md
│   │   ├── daily.sh / weekly.sh / monthly.sh
│   │   ├── glm-websearch-proxy.js  #     GLM/GPT web_search 代理（可选）
│   │   ├── glm-websearch-proxy.service
│   │   └── README.md
│   └── kiro-cli/                   #   Kiro-CLI 适配
│       ├── agent.md
│       ├── daily.sh / weekly.sh / monthly.sh
│       └── README.md
│
├── setup.sh                        # 交互式安装向导
├── LICENSE
└── README.md
```

## 快速开始

```bash
git clone <repo-url> tech-radar-port
cd tech-radar-port
bash setup.sh
```

安装向导会询问：
1. 目标平台（Claude Code / OpenCode / Kiro-CLI）
2. Agent 安装目录
3. 实例名称（如 `sensor`）
4. 报告输出目录
5. 是否自动写入 crontab

## 配置

安装完成后，编辑实例目录下的 `scan-config.yaml`：

- `domains`：定义搜集领域、关键词、重点跟踪实体
- `budget.mode`：`unlimited` / `standard` / `economy`（控制 token 消耗）
- `sources`：固定巡检的信息源 URL
- `signals`：由周报自动维护，记录趋势信号状态

`instance.env` 控制运行参数（超时、模型、输出路径）。

> **输出语言**：报告的输出语言由 `scan-config.yaml` → `meta.output_language` 字段控制，可设为 `Chinese` 或 `English`。

## 手动运行

```bash
# 日报
bash <install_dir>/scripts/daily.sh <instance_dir>

# 周报
bash <install_dir>/scripts/weekly.sh <instance_dir>

# 月报
bash <install_dir>/scripts/monthly.sh <instance_dir>
```

## 移植到新平台

如果目标平台不在已支持列表中，参考 [platforms/PORTING-GUIDE.md](platforms/PORTING-GUIDE.md)。
该指南面向 AI agent，包含完整的调研、适配、测试、排障流程。

## 依赖

| 依赖 | 安装方式 |
|------|---------|
| Python 3 | 系统自带或 `apt install python3` |
| pyyaml | `pip3 install pyyaml` |
| arxiv | `pip3 install arxiv` |
| AI 编码平台 CLI | Claude Code / OpenCode / Kiro-CLI 任选其一 |
