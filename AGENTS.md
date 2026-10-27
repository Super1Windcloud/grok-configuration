# Grok 全局全栈工程规范

用户级根规范，适用于所有工程。仓库内更深的 `AGENTS.md` 后加载，冲突时以工程规则为准。不要把本文件复制到 `~/.grok/rules/`，该目录同样全局加载，复制会造成同一规范加载两次。

## 1. 沟通

- 默认使用自然流畅的技术中文。代码标识符和专用英文术语保持原文。
- 直接说明结论、原因、风险和验证结果。不寒暄，不空泛说教。
- 引用工程文件与符号时，使用带行号范围的点击式 Markdown 链接，例如 `[PageManager.kt](file:///path/to/PageManager.kt#L10-L20)`。
- 需求边界不清时，先说明关键假定。高风险意图不靠猜测推进。
- 复合任务按需求收敛、影响分析、方案、实施、验证推进。低风险单点修改可以直接实施。

## 2. 命令与包管理

- 禁止裸 `cd`。使用工具的路径参数或绝对路径，例如 `git -C <path>`、`pnpm --filter <pkg>`、`cargo --manifest-path <path>`。
- 尊重锁文件：有 `pnpm-lock.yaml` 时不用 `npm install` 或 `yarn`；有 `bun.lock` 或 `bun.lockb` 时用 `bun`。
- Android 用工程里的 `./gradlew` 做目标模块局部编译和单测。只有需要可安装包时才做对应 assemble，默认不做全量 assemble。
- Rust 优先 `cargo check` 或 `cargo test -p <pkg>`。不随意 `cargo clean`。
- 读取文件前先确认真实路径。上下文或搜索结果没有给出路径时，先搜索再读，不凭后缀猜测 `.java` / `.kt`、`.ts` / `.tsx`。
- 临时文件放在 `/tmp`。用完删除。
- 长任务按后台与超时机制执行，不空转轮询阻断交互。

## 3. 最小改动与缓存

- 只改解决问题所需的代码。保留既有注释、文档和语言风格：Java 按 Java，Kotlin 按 Kotlin，Rust 按 Rust，TypeScript 按仓库现状。
- 不为局部需求做跨模块重命名、包路径迁移、批量格式化、导入重排或依赖大版本升级。
- 验证在工程工作区就地执行，复用已有 daemon 与构建缓存。不以隔离为由把仓库复制到 `/tmp` 或无缓存目录做冷编译。
- Git worktree 必须软链接复用主库的 `node_modules`、`target`、`.gradle`、`.cache`、`.venv`。
- 普通子任务留在当前工作区，共享已有缓存。高风险探索或破坏性重构才使用隔离 worktree，并同样链接主库缓存。

## 4. 验证

- 代码或配置改动完成后，用目标模块的最小自动化验证给出真实成功证据，再声明完成。分析、方案和纯说明不宣称已经跑过测试。
- 涉及 `minSdk`、浏览器或操作系统版本的改动要做显式条件防护，避免低版本运行时崩溃。

## 5. Git 交付

- 提交说明使用中文 Conventional Commits：`<type>(<scope>): <简明中文摘要>`。
- 不修改 git config。不 push、不 amend、不改写历史，除非用户明确要求。
- `git push`、`gh pr`、`gh release`、发布 crate 或 npm 只在用户明确要求时执行。
- 实现类任务的交付末尾输出：

```text
### 5. Git Commit Message
<type>(<scope>): <简明中文摘要>

- 改动要点
- 安全边界
- 验证证据
```

## 6. 授权

- 未经明确授权，不执行 `rm -rf`、`git reset --hard`、`git clean -fd`、`git push --force`、`sudo`，以及其他难撤回的删除、覆盖和对外发布。
- 权限或安全检查拒绝某条命令时，说明意图并等待确认。不改写命令形式绕过。

## 7. Android 与后端契约

分析 Android 运行时风险时，同时核对后端仓库 `~/super/pickaxe`。范围包括 API 契约、DTO 与 JSON 反序列化、字段可选性、错误码、推送、时序状态机和降级。不单凭客户端推测服务端行为。核对真实数据结构、枚举、边界和版本兼容，避免空指针、反序列化失败和静默业务错误。
