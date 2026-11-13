# Adaptive LP Vault

双资产流动性管理 monorepo：根据链上价格信号，在 Uniswap V2、两个 V3 费率池和持币状态之间切换。用户持有可转让的 ERC-20 份额，前端通过钱包直接调用合约。

## 工程布局

- `contract/`：Solidity 0.8.24 / Foundry 合约、测试、生产部署脚本、本地环境与持续交易模拟工具。
- `frontend/`：Vite + React + TypeScript + Ant Design + wagmi，使用容器—展示组件分层。
- 根目录：npm workspaces、锁文件与持续集成。

## 开始使用

需要 Node.js 24、npm 11、Foundry（验证版本 1.5.1）及浏览器以太坊钱包。

```bash
git submodule update --init --recursive
npm ci
npm ci --prefix contract/lib/uniswap-test-deps --ignore-scripts --no-audit --no-fund
npm run abi
```

分别在三个终端运行：

```bash
# 终端 1：本地链，保持运行
npm run chain
```

```bash
# 终端 2：部署官方 Uniswap 与 Vault，完成预言机预热及初始化
npm run local:deploy
# 部署完成后启动前端
npm run dev
```

```bash
# 终端 3：独立持续交易进程；Ctrl+C 只停止交易，不停止链和前端
npm run market -- --scenario steady
```

访问 `http://127.0.0.1:5173`。将钱包连接到 RPC `http://127.0.0.1:8545`、链 ID `31337`，导入 Anvil 开发账户。前端没有内置私钥，也不会自动代替用户执行再平衡。

本地部署命令由 TypeScript 组织阶段调用，链上部署与配置均通过 Foundry 广播。本地专用脚本、工具、模拟器、测试及使用说明集中在 `contract/local/`，业务部署复用 `contract/script/` 中的正式脚本。详细阶段与失败恢复说明见[本地运行手册](contract/local/README.md)。

首次部署会拒绝重复使用已执行过部署的账户。需要全新环境时，先停止交易进程和 Anvil，再重新启动链、重新部署并刷新页面。具体账户、场景、初始化前模式与恢复说明见[本地运行手册](contract/local/README.md)。

## 功能

- 公开资产总览、真实预言机信号、仓位区间与最近链上事件。
- 双资产存款、精确额度授权、双资产赎回、份额转让和委托赎回授权。
- 普通再平衡、Keeper / Manager 受控换币再平衡。
- Guardian 单向收紧控制与紧急退出；Manager 初始化、适配器和暂停管理。
- 根管理员业务角色授撤、两阶段交接、延迟变更及明确确认的根角色注销。
- 本地官方 V2/V3 连续真实 Swap，以及平稳、趋势、冲击、恢复场景。

## 验证命令

```bash
npm run contract:build
npm run contract:test
npm run lint
npm test
npm run build
npx playwright install chromium
# 自动创建独立端口的临时 Anvil，验证 Foundry 部署各模式并恢复公开清单：
npm run test:deployment
# 额外自动启动临时前端，运行两种浏览器流程与市场回归：
npm run test:deployment -- --browser
# 本地链、部署和前端已运行，且交易进程已停止时执行：
npm run test:e2e
```

`npm run abi` 只构建运行时所需合约并导出接口；`contract:build` / `contract:test` 保留完整合约编译与回归。首次完整 via-IR 测试编译可能较慢。

## 文档

- [前端分层与权限实现](frontend/README.md)
- [本地部署和交易模拟](contract/local/README.md)
- [产品规则](contract/docs/PRODUCT_SPEC.md) · [合约架构](contract/docs/ARCHITECTURE.md)
- [合约测试指南](contract/test/README.md)
- [生产部署手册](contract/script/DEPLOYMENT_RUNBOOK.md) · [生产环境变量](contract/.env.example)

本地代币为测试资产，不代表美元、真实 ETH 或任何真实价值。价格偏离不是收益预测，模拟成交不是收益承诺。测试通过不代表已完成安全审计或生产发布验收。
