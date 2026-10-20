# 验证记录

## mitmproxy MCP 验证（2026-10-20）

- `grok` 本机配置已增量接入 `mitmproxy-mcp==0.6.1`，Python 3.13，附加 `mcp<2` 兼容约束。安装脚本已纳入完整安装流程，也可独立执行。
- `python3 -B -m unittest discover -s tests -q`：37 项通过。其中新增 7 项覆盖配置保留与备份、重复执行、dry-run、依赖失败保护、配置/运行目录软链接防御、缺少 uvx 和所属客户端边界。
- 读取本机真实 MCP 启动配置并执行 stdio `initialize`、`tools/list`、`list_rules`：全部通过，发现 25 个工具。
- 对照修改前备份作结构比较：除新增 MCP 外，原有配置完整保留；备份不入库。
- `grok mcp doctor mitmproxy-mcp --json`：healthy=true，协议 2025-11-25，25 个工具。专用 uv 缓存与工具目录位于 `~/.grok/runtime/mitmproxy/`，保持原有沙箱限制。
- 验证未更改系统代理与证书信任；真实设备、HTTPS 信任配置和外部业务抓包不属于本次验收。新客户端会话加载此 MCP。
