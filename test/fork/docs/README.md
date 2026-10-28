# Ethereum 主网 Fork 测试

在固定历史区块的本地主网分叉上，部署项目生产合约并连接真实 USDC/WETH、Uniswap 池和路由器。测试不会广播主网交易，无需私钥或 npm 编译产物。逐函数覆盖和故障注入见 [测试函数目录](FORK_TEST_REVIEW.md)。

## 运行

需要能读取历史账户、代码和存储的 Ethereum 主网归档 RPC（远程节点），在仓库根目录执行：

```bash
export MAINNET_RPC_URL='https://YOUR_ETHEREUM_ARCHIVE_RPC'
FOUNDRY_PROFILE=fork forge test -vv

# 只运行一组。
FOUNDRY_PROFILE=fork forge test --match-contract DepositRedeemForkTest -vv
```

- 必须选择 `fork` 配置；默认配置排除此组，仅传 `--match-path` 无法取消排除。
- RPC 缺失或不可用会使初始化失败，不会跳过或回退到本地替身。持续集成应单独运行，并确认用例数大于零。

## 基线与参数

- 默认：Ethereum Mainnet，区块 [`21,000,000`](https://etherscan.io/block/21000000)，资产为 USDC（6 位）/ WETH（18 位）。
- 地址、资金准备和策略参数集中在 [`MainnetForkFixture.sol`](../helpers/MainnetForkFixture.sol)：USDC 通过真实持币账户转入，WETH 通过包装 ETH 获得，不直接改写 Token 余额或池储备。
- 资产核对容差为 USDC `10` 个最小单位、WETH `2,000,000,000` wei，是绝对取整额度，不是百分比损失。
- 可用 `MAINNET_FORK_BLOCK` 临时指定其他区块，地址不随之改变；正式更换基线时须重新核对历史数据、余额、策略路径和容差。测试阈值及资产选择不代表生产参数已确定。

## 关键边界

- 使用真实历史价格观测；仅推进时间不会产生交易，也不是重放未来行情。
- 普通迁移会先补足目标仓位短缺的 Token；需调整比例的流程由换币测试单独检查。
- 个别用例注入历史读取或建仓失败；回滚检查只覆盖记录的字段，不代表比较全部存储。
- 本组不覆盖三阶段部署脚本、签名广播、多链发布验收、非标准 Token、USDC 黑名单/升级故障、完整历史重放或交易排序攻击，不能代替安全审计。
