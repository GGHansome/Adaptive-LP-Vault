# 测试指南

所有命令均在仓库根目录执行。

## 运行

```bash
# 单元测试：无需 npm 依赖或远程节点。
forge test --match-path 'test/unit/*.t.sol'

# 首次运行本地集成和不变量测试前安装依赖。
npm ci --prefix lib/uniswap-test-deps --ignore-scripts --no-audit --no-fund
forge test                  # 离线回归，不包含主网分叉测试
```

按测试类型查阅：

- **单元**：组件逻辑、边界和故障行为；见 [函数目录](unit/docs/UNIT_TEST_REVIEW.md)。
- **集成**：生产合约与本地官方 Uniswap 合约配合；见 [运行指南](integration/docs/README.md) · [函数目录](integration/docs/INTEGRATION_TEST_REVIEW.md)。
- **不变量**：随机操作序列下的资产、份额和权限检查；见 [运行指南](invariant/docs/README.md) · [函数目录](invariant/docs/INVARIANT_TEST_REVIEW.md)。
- **主网分叉（Fork）**：固定历史区块的真实资产和协议兼容性，需要归档 RPC（可读取历史状态的远程节点）；见 [运行指南](fork/docs/README.md) · [函数目录](fork/docs/FORK_TEST_REVIEW.md)。

## 辅助代码放置

- 各类测试专用环境和参考算法放在本类 `helpers/`，测试替身放在本类 `mocks/`；随机操作生成器放在 `invariant/handlers/`。
- 至少两类测试实际共用后，才放入顶层 `helpers/` 或 `mocks/`。目前共用环境是 `helpers/LocalUniswapFixture.sol`；其小型测试 Token `LocalTestToken` 同文件定义，供环境和随机操作生成器使用。
- 仅供单个测试使用的辅助函数、`vm.mockCall()` 和故障输入留在用例附近。
- 直接导入辅助文件，不通过 `.t.sol` 间接导入；新套件仅需环境时继承 helper，不继承具体测试套件，以免重复执行用例。

修改测试行为时同步更新对应函数目录；移动辅助代码时更新导入路径并运行回归。
