# Grok Build Configuration & Statusline

## Quick Start（快速开始）

以下命令假定仓库已位于 `~/super/grok-configuration`；其他位置请替换为实际绝对路径，命令可从任意工作目录执行。

### 1. 准备环境

准备 Bash、Python 3.11+、Git 和 uv（提供 `uvx`），并单独安装、完成 Grok Build 客户端的登录或 API 凭据配置。安装脚本部署 Harness 配置与插件，不负责客户端本体和账号登录。

```bash
python3 --version
command -v git uvx grok
```

### 2. 将仓库配置安装到本机

```bash
# 先预览：不写入、不下载
~/super/grok-configuration/install.sh --dry-run
# 再安装：部署配置并联网恢复插件、依赖
~/super/grok-configuration/install.sh
```

覆盖前的文件备份到 `~/.harness-backups/`。安装后查看输出中的失败或待安装项，重启 Grok Build 客户端或新建会话加载配置；需要授权的插件和 MCP 在客户端完成授权。

### 3. 验证与日常备份

验证仓库脚本：

```bash
python3 -B -m unittest discover -s ~/super/grok-configuration/tests -v
```

本机配置调整后，再将本机配置导出到仓库并检查差异：

```bash
~/super/grok-configuration/sync.sh
git -C ~/super/grok-configuration diff --stat
git -C ~/super/grok-configuration diff
```

`install.sh` 的方向是「仓库 → 本机」，`sync.sh` 的方向是「本机 → 仓库」；新机器还原从安装开始。同步会修改仓库文件，不会自动 commit 或 push，提交前检查差异中是否含敏感内容。单测验证脚本行为，实际插件和 MCP 是否可用仍需在客户端确认。

安装与同步仅操作 `~/.grok/`，不读写其他 agent 或 `~/.agents/` 的配置。`--only` 仅接受本仓库所属 agent，跨 agent 参数会在执行前报错；`--repo` 不会扩大范围。

专为 **Grok Build**（Grok CLI 1.0.60+ / 1.0.62+）深度定制的高性能异步非阻塞状态栏与全栈工程配置。深度融合 **Codex**、**Claude Code** 与 **Antigravity CLI** 的最佳实践、自动化权限策略与物理级性能调优，并接入统一的 Multi-Harness 一键安装与配置同步体系。

---

## ✨ 核心特性

- 🚀 **极致低延迟（~28ms）**：
  - 纯物理级 Python 3 原生解析，跳过环境管理器（如 mise/asdf/pyenv）的多层 Shim 寻址；
  - 零外部依赖，极简导入，冷启动开销极低；
  - Git 脏状态（Dirty Check）全异步后台刷新 + 4s TTL 临时缓存，在大仓库中主线程耗时由数百毫秒降至 **< 1ms**。
- 🌿 **全场景 Git 上下文感知**：
  - 原生支持常规分支、Detached HEAD（自动截取前 7 位 commit hash）；
  - 支持复杂 Git 状态指示：变基中 `[rebase]`、合并冲突 `[merge]`、挑拣中 `[cherry-pick]` 以及未暂存标记 `*`；
  - 原生支持 **Git Worktree**（提取 `worktree.name` 或 `workspace.git_worktree`，以 `[wt:name]` 标注）。
- 📊 **Token 上下文用量多维透视**：
  - 突破单一百分比，提供 `ctx:18% (36k/200k)` 真实用量透视，一眼洞察单轮上下文吞吐与总量边界；
  - 动态警报色阶：使用率 `< 75%` 柔和显示，`≥ 75%` 黄色预警（`\033[1;33m`），`≥ 90%` 红色警戒（`\033[1;31m`）。
- ⏱️ **Turn 执行时序感知**：
  - 会话交互中：读取 `turn.started_at_ms` 动态计算本轮实时耗时（`running:8s`，绿色醒目显示）；
  - 单轮完成后：按该 prompt 的起点到回合结束冻结耗时（`took:14s`）。下一条 prompt 从 0 重新计时。`cost.total_duration_ms` 是进程挂上会话后的累计时长，不参与这个数字。
- 💰 **成本与模型指标透明**：
  - 显示当前会话模型及推理深度（如 `Grok 4.7 (high)`）；
  - 自动呈现累计会话消费（如 `$0.02`）。
- 📐 **智能路径收敛与弹性对齐**：
  - `smart_cwd`：Git 仓库内自动锚定 `仓库名/.../子目录`，非 Git 路径自动折叠 `$HOME` 为 `~`；
  - 两端弹性对齐：左侧显示状态指标，右侧显示项目路径，根据终端列宽（`COLUMNS` / 终端 TTY）自动计算弹性间隙，窄屏优雅降级。
- 🛡️ **标准 Harness 架构统一纳管**：
  - 原生接入 `scripts/harness.py` 跨端配置框架，与 `codex-configuration`、`fullstack-claude-code-configuration`、`antigravity-statusline-configuration` 保持 100% 一致的 `install.sh` 与 `sync.sh` 调用契约；
  - 自动备份老配置至 `~/.harness-backups/`，安全保护本地秘钥凭据；
  - 自动化受控插件恢复：支持 Testkit 插件的无感安装与 `--trust` 授权。

---

## 📸 显示效果样例

### 1. 活跃生成轮次中（Active Turn）
```text
git:main* Grok 4.7 (high) ctx:18% (36k/200k) running:8s $0.01              super/grok-configuration
```

### 2. 交互就绪状态（Completed Turn with Session Name）
```text
git:feature/auth auth-refactor Grok 4.7 ctx:42% (84k/200k) took:14s $0.04        super/codex-configuration
```

### 3. 上下文高水位预警（High Context Alert ≥ 90%）
```text
git:main [merge]* Grok 4.6 ctx:92% (184k/200k) took:45s $0.12                                  my-large-repo
```

---

## 🚀 快速安装与配置同步

与体系内其他 Harness 工具保持完全统一的操作接口：

### 一键安装
```bash
/path/to/grok-configuration/install.sh
```

### 预览安装（Dry-run）
```bash
/path/to/grok-configuration/install.sh --dry-run
```

### 离线部署（跳过网络插件下载）
```bash
/path/to/grok-configuration/install.sh --offline
```

### 配置同步（从本机 ~/.grok 同步回仓库并自动脱敏凭据）
```bash
/path/to/grok-configuration/sync.sh
```

---

## ⚙️ Grok Build 配置规范

在 `~/.grok/config.toml` 中配置 `[ui.status_line]`：

```toml
[ui.status_line]
type = "command"
command = "~/.grok/statusline.sh"
# refresh_interval = 300   # 可选：空闲期周期性刷新的秒数 (1-86400)
```

> **说明**：Grok 在启动时读取 `config.toml`，修改后重启 Grok 交互客户端即可生效。脚本文件变动则实时在下一轮状态更新中生效。

---

## 🧪 自动化测试验证

运行完整自动化测试套件：
```bash
python3 -m unittest discover -s /path/to/grok-configuration/tests -v
```

测试覆盖范围包括：
- **安装隔离测试**：真实 shell 入口验证其他 agent 与共享配置保持原样、跨 agent 参数拒绝、同步仅读取自身配置、预览无写入；本轮完整 Python 套件 30 项通过。
- **Harness 测试**：配置导出凭据脱敏、软链接安全隔离、插件受控安装、备份保护与独立 layout 导出；
- **Statusline 测试**：Token 格式化（`500`, `1.5k`, `24k`, `1.2M`）、用量推算、色阶阶梯响应（`<75%`, `75%~89%`, `≥90%`）、时序感知（`running:8s` / `took:14s`）、`smart_cwd` 多级折叠、CJK 双宽字符真实排版与端到端 Mock JSON 运行。

---

## 🛠️ 文件目录结构

```text
.
├── .gitignore                      # 忽略缓存与编译临时文件
├── .harness.json                   # Harness 拓扑布局声明
├── LICENSE                         # MIT 开源许可证
├── README.md                       # 说明与技术文档
├── AGENTS.md                       # 用户级根规范，随 sync/install 部署到 ~/.grok/
├── config.toml                     # Grok Build 生产环境脱敏配置
├── config.toml.example             # Grok Build 推荐配置参考
├── install.sh                      # 一键部署与无缝安装入口
├── plugins.json                    # 声明受控插件与技能源（Testkit）
├── scripts/
│   └── harness.py                  # 跨端通用配置与插件管理引擎
├── statusline.sh                   # 状态栏核心脚本（Python 3 实现，~28ms）
├── sync.sh                         # 双向安全同步入口
└── tests/
    ├── test_harness.py             # Harness 部署与安全测试套件
    └── test_statusline.py          # 状态栏核心逻辑测试套件
```


## mitmproxy MCP

默认安装会增量接入 [snapspecter/mitmproxy-mcp](https://github.com/snapspecter/mitmproxy-mcp)。需要已安装 `uv`（提供 `uvx`）；使用 Python 3.13、固定 PyPI 版本 `0.6.1`，额外约束 `mcp<2`，避免该版本误装不兼容的 MCP SDK 2.x。首次运行由 uv 准备 Python 和依赖，后续复用 uv 缓存。

仅接入此 MCP（不重装其他工具或插件）：

```sh
python3 ~/super/grok-configuration/scripts/mitmproxy_setup.py --dry-run
python3 ~/super/grok-configuration/scripts/mitmproxy_setup.py
```

脚本仅修改本仓库所属客户端的一条 MCP 配置；覆盖前保存到 `~/.harness-backups/mitmproxy-*`，保留其他 MCP、凭据与项目设置，拒绝向软链接目标写入。`--offline` 只写配置、不下载或验证依赖；`--dry-run` 不写入、不下载。完整安装的 `--dependencies none` 跳过此步骤。

抓包数据库位于 `~/.local/share/harness-mitmproxy/<agent>/`（私有目录），不写入工作项目或 GitHub。启动 MCP 不会自动启动代理；需要抓包时调用 `set_scope`、`start_proxy`（默认 `127.0.0.1:8080`），完成后调用 `stop_proxy`。多个 agent 同时抓包应使用不同端口；应用代理、HTTPS 证书信任按目标设备配置。本次接入不更改系统代理或证书信任。客户端重启或新会话后加载新 MCP。

Grok 的 workspace 沙箱限制向 `~/.grok/` 之外写入，因此 Grok 专用运行目录与 uv 缓存位于 `~/.grok/runtime/mitmproxy/`，通过 MCP 子进程的 `UV_CACHE_DIR` 配置，不放宽沙箱。
