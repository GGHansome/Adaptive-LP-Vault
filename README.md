# Adaptive LP Vault

双资产流动性管理合约：根据链上价格信号，在 Uniswap V2、两个 V3 费率池和直接持币状态之间切换，用户以 ERC-20 份额持有资产权益。使用 Foundry 和 Solidity 0.8.24 开发。

## 快速开始

安装 [Foundry](https://book.getfoundry.sh/getting-started/installation) 后，在仓库根目录执行：

```bash
forge build

# 首次运行本地集成和不变量测试前安装官方 Uniswap 编译产物。
npm ci --prefix lib/uniswap-test-deps --ignore-scripts --no-audit --no-fund
forge test
```

普通回归不包含主网分叉测试，安装依赖后可离线运行。测试分组和单独运行命令见 [测试指南](test/README.md)。

## 常用命令

```bash
forge fmt         # 格式化
forge snapshot    # Gas 快照
```

## 文档入口

- [产品规则](docs/PRODUCT_SPEC.md) · [合约架构](docs/ARCHITECTURE.md)
- [测试指南](test/README.md)
- [环境变量示例](.env.example)
- [部署操作手册](script/DEPLOYMENT_RUNBOOK.md)：部署、配置、初始化三阶段的检查和命令。

测试通过不代表已完成安全审计或生产发布验收；部署脚本全流程需单独验证。
