# 合约工作区

当前目录是独立的 Foundry 项目根目录。合约文档中的“仓库根目录”或 `forge` 命令，均应在本目录执行；monorepo 入口与 npm 命令在上一级目录。

```bash
forge build
npm ci --prefix lib/uniswap-test-deps --ignore-scripts --no-audit --no-fund
forge test
forge fmt --check
```

- [产品规则](docs/PRODUCT_SPEC.md) · [合约架构](docs/ARCHITECTURE.md)
- [测试指南](test/README.md) · [生产部署操作手册](script/DEPLOYMENT_RUNBOOK.md)
- [本地部署和交易模拟](local/README.md) · [环境变量示例](.env.example)
- [完整项目入口](../README.md)

生产合约位于 `src/`，正式部署脚本位于 `script/`。本地部署、测试资产、交易模拟器及其验收和说明集中在 `local/`；通用前端 ABI 导出工具位于 `tools/export-abi.ts`。本地流程复用正式部署脚本，使用方法和失败恢复统一见 `local/README.md`。
