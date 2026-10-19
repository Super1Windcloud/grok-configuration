# Grok Configuration & Statusline
专为 **Grok Build**（Grok CLI 1.0.60+ / 1.0.62+）深度定制的高性能异步非阻塞状态栏，深度融合并延续 **Antigravity CLI** 状态栏的设计哲学与物理级性能调优。

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
  - 会话交互中：读取 `turn.started_at_ms` 动态计算实时耗时（`running:8s`，绿色醒目显示）；
  - 单轮完成后：读取 `cost.total_duration_ms` 显示单轮耗时（`took:14s`）。
- 💰 **成本与模型指标透明**：
  - 显示当前会话模型及推理深度（如 `Grok 4.7 (high)`）；
  - 自动呈现累计会话消费（如 `$0.02`）。
- 📐 **智能路径收敛与弹性对齐**：
  - `smart_cwd`：Git 仓库内自动锚定 `仓库名/.../子目录`，非 Git 路径自动折叠 `$HOME` 为 `~`；
  - 两端弹性对齐：左侧显示状态指标，右侧显示项目路径，根据终端列宽（`COLUMNS` / 终端 TTY）自动计算弹性间隙，窄屏优雅降级。

---

## 📸 显示效果样例

### 1. 活跃生成轮次中（Active Turn）
```text
git:main* Grok 4.7 (high) ctx:18% (36k/200k) running:8s $0.01              super/grok-statusline-configuration
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

## 🚀 快速安装与部署

### 一键安装
```bash
/Users/super/super/grok-statusline-configuration/install.sh
```

### 预览安装（Dry-run）
```bash
/Users/super/super/grok-statusline-configuration/install.sh --dry-run
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

运行单元测试套件：
```bash
python3 /Users/super/super/grok-statusline-configuration/tests/test_statusline.py
```

测试覆盖范围包括：
- Token 数量单位格式化（`500`, `1.5k`, `24k`, `1.2M`）；
- 上下文用量计算（直接百分比、剩余反推、Token 比例推算）；
- 警戒色阶阶梯响应（`<75%`, `75%~89%`, `≥90%`）；
- 耗时格式化与运行中/完成态时序识别；
- 成本边界格式化；
- `smart_cwd` 多级路径折叠；
- CJK 双宽字符与 ANSI 转义序列真实宽度对齐；
- 弹性左右对齐与窄屏降级；
- Mock JSON 真实命令行端到端执行流。

---

## 🛠️ 文件目录结构

```text
.
├── .gitignore                      # 忽略缓存与编译临时文件
├── README.md                       # 说明与技术文档
├── config.toml.example             # Grok Build 推荐配置参考
├── install.sh                      # 一键部署与无缝安装脚本
├── statusline.sh                   # 状态栏核心脚本（Python 3 实现，~28ms）
├── sync.sh                         # 双向同步脚本
└── tests/
    └── test_statusline.py          # 完整自动化测试套件
```
>>>>>>> 69e8dc6 (feat(statusline): 引入 Grok Build 高性能异步状态栏与配置管理)
