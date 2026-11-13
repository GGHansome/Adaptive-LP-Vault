# 本地集成测试

在本地部署官方 Uniswap 合约，检查生产合约的存赎、手续费、迁移、换币和故障恢复。无需远程节点、私钥或链上资金。逐函数覆盖见 [测试函数目录](INTEGRATION_TEST_REVIEW.md)。

## 运行

在仓库根目录执行：

```bash
npm ci --prefix lib/uniswap-test-deps --ignore-scripts --no-audit --no-fund
forge test --match-path 'test/integration/*.t.sol' -vv
```

依赖版本与完整性由 [`package-lock.json`](../../../lib/uniswap-test-deps/package-lock.json) 锁定，安装后可离线运行。官方旧版合约使用发布包字节码部署，不参与项目 Solidity 编译。

## 环境与边界

- 官方依赖：V2 Core `1.0.1`、V3 Core `1.0.1`、V3 Periphery `1.4.4`。共用部署见 [`LocalUniswapFixture.sol`](../../helpers/LocalUniswapFixture.sol)，本类操作与检查见 [`IntegrationTestFixture.sol`](../helpers/IntegrationTestFixture.sol)。
- 使用可铸造的普通 ERC-20 测试 Token；存赎场景覆盖 18/18、6/18、18/6、6/6 位精度，不代表所有场景都执行了四种组合。
- 初始价格按两种 Token 的最小单位 1:1 设置，不代表每整枚资产等价。取整检查使用明确的最小单位额度，不是百分比亏损额度。
- 多数策略场景控制预言机 `snapshot()` 输入，报价、池和交易仍真实执行；少数用例故意让指定调用失败。具体设置和限制见函数目录。
- 本组不验证部署脚本、主网状态、非标准 Token、原生 ETH 或 NFT 元数据。主网兼容性见 [Fork 测试](../../fork/docs/README.md)，长随机序列见 [不变量测试](../../invariant/docs/README.md)。

升级官方编译产物时，同时更新依赖版本和锁文件，并运行完整回归。
