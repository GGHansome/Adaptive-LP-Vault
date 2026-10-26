# Adaptive LP Vault 部署执行手册

- 状态：Draft（执行脚本已实现，真实网络地址和参数仍需部署负责人确认）
- 适用网络：Ethereum Mainnet 或与 Uniswap V2/V3 接口兼容的测试网络
- 工具：Foundry、`forge`、`cast`
- 部署脚本：`script/Deploy.s.sol`、`script/Configure.s.sol`、`script/Bootstrap.s.sol`
- 部署规范：[DEPLOYMENT.md](DEPLOYMENT.md)

本文是实际执行手册。它不替代产品规则、架构约束或安全审计结论。所有金额均为对应 Token 的 raw units（最小单位），所有地址必须使用校验和地址并保存到部署记录。

## 1. 脚本执行内容

部署流程分为三个脚本阶段：

1. `DeployAdaptiveLPVault`：部署 `VaultStrategyMath`、`VaultComponentFactory`、`CanonicalV3Oracle`、`AdaptiveLPVault`、一个 V2 Adapter 和两个 V3 Adapter。脚本在运行时将策略库地址链接进 Vault creation code，并写入 `deployments/<chainId>.json`。
2. `ConfigureAdaptiveLPVault`：使用 Default Admin 授予 Manager、Guardian、Keeper，再使用 Manager 在专属 `VaultControl` 注册三个 Adapter。
3. `BootstrapAdaptiveLPVault`：使用 Manager 为 Vault 批准两个底层 Token，并执行一次性 `bootstrap()`。

脚本不会自动完成以下链下发布门禁：浏览器源码验证、第三方 Router 报价、双向价格影响计算、Mainnet Fork 完整业务流程验证和人工审批。这些检查必须在发送 Bootstrap 前完成，并把结果写入部署记录。

## 2. 前置条件

### 2.1 安装和检查 Foundry

```bash
foundryup
forge --version
cast --version
anvil --version
```

在项目根目录执行：

```bash
cd /Users/gaoxu/Desktop/Code/AdaptiveLPVault
forge install
forge build
```

如果依赖已经存在，`forge install` 可以跳过。部署前应固定并记录：

```bash
git rev-parse HEAD
forge --version
cat foundry.toml
```

### 2.2 生成执行账户地址

部署脚本直接从环境变量读取私钥，不把私钥写入 Solidity、命令历史或部署记录。下面命令只用于从私钥计算地址：

```bash
export DEPLOYER_PRIVATE_KEY=0x...
export ADMIN_PRIVATE_KEY=0x...
export MANAGER_PRIVATE_KEY=0x...

export DEPLOYER=$(cast wallet address --private-key "$DEPLOYER_PRIVATE_KEY")
export DEFAULT_ADMIN=$(cast wallet address --private-key "$ADMIN_PRIVATE_KEY")
export MANAGER=$(cast wallet address --private-key "$MANAGER_PRIVATE_KEY")

export GUARDIAN=0x...
export KEEPER=0x...

printf 'DEPLOYER=%s\nDEFAULT_ADMIN=%s\nMANAGER=%s\nGUARDIAN=%s\nKEEPER=%s\n' \\
  "$DEPLOYER" "$DEFAULT_ADMIN" "$MANAGER" "$GUARDIAN" "$KEEPER"
```

`DEFAULT_ADMIN` 必须与 `ADMIN_PRIVATE_KEY` 对应，`MANAGER` 必须与 `MANAGER_PRIVATE_KEY` 对应。部署者、管理员和 Manager 可以是同一账户，也可以分开；分开时必须由部署负责人确认权限传递和私钥保管方式。

### 2.3 创建环境文件

建议使用未提交的 `.env` 文件：

```bash
cat > .env <<'EOF'
RPC_URL=https://YOUR_RPC_ENDPOINT
DEPLOYER_PRIVATE_KEY=0xYOUR_DEPLOYER_PRIVATE_KEY
ADMIN_PRIVATE_KEY=0xYOUR_ADMIN_PRIVATE_KEY
MANAGER_PRIVATE_KEY=0xYOUR_MANAGER_PRIVATE_KEY
DEPLOYER=0xYOUR_DEPLOYER_ADDRESS
DEFAULT_ADMIN=0xYOUR_DEFAULT_ADMIN_ADDRESS
MANAGER=0xYOUR_MANAGER_ADDRESS
GUARDIAN=0xYOUR_GUARDIAN_ADDRESS
KEEPER=0xYOUR_KEEPER_ADDRESS

# 外部协议地址。必须来自目标网络的官方部署信息。
CANONICAL_POOL=0xYOUR_CANONICAL_UNISWAP_V3_POOL
V2_POOL=0xYOUR_UNISWAP_V2_PAIR
LOW_FEE_POOL=0xYOUR_LOW_FEE_UNISWAP_V3_POOL
HIGH_FEE_POOL=0xYOUR_HIGH_FEE_UNISWAP_V3_POOL
UNISWAP_V2_FACTORY=0xYOUR_UNISWAP_V2_FACTORY
UNISWAP_V3_FACTORY=0xYOUR_UNISWAP_V3_FACTORY
ROUTER=0xYOUR_APPROVED_UNISWAP_V3_ROUTER
POSITION_MANAGER=0xYOUR_UNISWAP_V3_POSITION_MANAGER

# Oracle 配置。short window 必须严格小于 long window。
TWAP_WINDOW_SECONDS=1800
SHORT_TWAP_WINDOW_SECONDS=300

# Vault immutable 配置，使用 raw units。
VAULT_NAME=Adaptive LP Vault
VAULT_SYMBOL=ALPV
DUST_TOLERANCE0=1
DUST_TOLERANCE1=1
MINIMUM_LOCKED_SHARES=1000000000000000
MINIMUM_INITIAL_NAV=1
DEFAULT_ADMIN_DELAY=86400

# 策略 immutable 配置。
MIN_REBALANCE_COOLDOWN=3600
ENTER_MEDIUM_BPS=100
EXIT_MEDIUM_BPS=50
ENTER_HIGH_BPS=300
EXIT_HIGH_BPS=200
ENTER_EXTREME_BPS=1000
EXIT_EXTREME_BPS=800
NARROW_RANGE_HALF_WIDTH_STEPS=10
WIDE_RANGE_HALF_WIDTH_STEPS=50
MIN_RECENTER_BPS=2500
MAX_HEALTHY_IDLE_BPS=500
MAX_SWAP_SLIPPAGE_BPS=100
MAX_MIGRATION_LOSS_BPS=50

# Bootstrap 配置，使用 token0/token1 raw units。
BOOTSTRAP_SENDER=0xYOUR_MANAGER_ADDRESS
BOOTSTRAP_RECEIVER=0xYOUR_INITIAL_SHARE_RECEIVER
BOOTSTRAP_AMOUNT0=1
BOOTSTRAP_AMOUNT1=1

# 可选；默认是 deployments/<chainId>.json。
# DEPLOYMENT_FILE=deployments/1.json
EOF

set -a
source .env
set +a
```

`.env` 必须加入 `.gitignore`。示例中的参数不是生产推荐值；特别是 `DUST_TOLERANCE*`、策略阈值、窗口、Bootstrap 金额和角色地址必须根据目标资产与发布审批填写。

## 3. 部署前检查

### 3.1 网络和账户余额

```bash
export CHAIN_ID=$(cast chain-id --rpc-url "$RPC_URL")
printf 'chainId=%s\n' "$CHAIN_ID"
cast balance "$DEPLOYER" --rpc-url "$RPC_URL"
cast balance "$DEFAULT_ADMIN" --rpc-url "$RPC_URL"
cast balance "$MANAGER" --rpc-url "$RPC_URL"
```

确认目标 `chainId`、原生币余额和 RPC 节点均符合发布记录。真实部署使用固定 RPC 和固定确认策略，不要在执行过程中切换网络。

### 3.2 检查外部合约代码

```bash
for address in \
  "$CANONICAL_POOL" "$V2_POOL" "$LOW_FEE_POOL" "$HIGH_FEE_POOL" \
  "$UNISWAP_V2_FACTORY" "$UNISWAP_V3_FACTORY" "$ROUTER" "$POSITION_MANAGER"; do
  test "$(cast code "$address" --rpc-url "$RPC_URL")" != "0x" || {
    echo "missing contract code: $address" >&2
    exit 1
  }
done
```

### 3.3 检查 canonical Pool 和 Factory 绑定

```bash
cast call "$CANONICAL_POOL" 'factory()(address)' --rpc-url "$RPC_URL"
cast call "$CANONICAL_POOL" 'token0()(address)' --rpc-url "$RPC_URL"
cast call "$CANONICAL_POOL" 'token1()(address)' --rpc-url "$RPC_URL"
cast call "$CANONICAL_POOL" 'fee()(uint24)' --rpc-url "$RPC_URL"
cast call "$CANONICAL_POOL" 'tickSpacing()(int24)' --rpc-url "$RPC_URL"
cast call "$UNISWAP_V3_FACTORY" \
  'getPool(address,address,uint24)(address)' \
  "$(cast call "$CANONICAL_POOL" 'token0()(address)' --rpc-url "$RPC_URL")" \
  "$(cast call "$CANONICAL_POOL" 'token1()(address)' --rpc-url "$RPC_URL")" \
  "$(cast call "$CANONICAL_POOL" 'fee()(uint24)' --rpc-url "$RPC_URL")" \
  --rpc-url "$RPC_URL"
```

最后一条返回值必须等于 `CANONICAL_POOL`。对 `V2_POOL`、`LOW_FEE_POOL` 和 `HIGH_FEE_POOL` 执行同类 Pool、Factory、Token 顺序和注册关系检查。

### 3.4 检查策略参数关系

```bash
python3 - <<'PY'
import os
v = {k: int(os.environ[k]) for k in [
    'EXIT_MEDIUM_BPS', 'ENTER_MEDIUM_BPS', 'EXIT_HIGH_BPS',
    'ENTER_HIGH_BPS', 'EXIT_EXTREME_BPS', 'ENTER_EXTREME_BPS',
    'MAX_HEALTHY_IDLE_BPS', 'MAX_SWAP_SLIPPAGE_BPS', 'MAX_MIGRATION_LOSS_BPS'
]}
assert 0 <= v['EXIT_MEDIUM_BPS'] < v['ENTER_MEDIUM_BPS'] <= v['EXIT_HIGH_BPS'] < v['ENTER_HIGH_BPS'] <= v['EXIT_EXTREME_BPS'] < v['ENTER_EXTREME_BPS']
assert 0 <= v['MAX_HEALTHY_IDLE_BPS'] < 10_000
assert 0 < v['MAX_SWAP_SLIPPAGE_BPS'] <= 10_000
assert 0 <= v['MAX_MIGRATION_LOSS_BPS'] <= 10_000
assert int(os.environ['SHORT_TWAP_WINDOW_SECONDS']) < int(os.environ['TWAP_WINDOW_SECONDS'])
print('strategy and window checks passed')
PY
```

## 4. Fork 和测试门禁

在真实部署前，先执行本地测试：

```bash
forge fmt --check
forge build
forge test
```

如果目标网络有 RPC，执行 Fork 测试。具体测试是否需要额外环境变量，以测试文件为准：

```bash
forge test --fork-url "$RPC_URL" --match-path 'test/fork/*.t.sol' -vvv
```

必须额外验证 Oracle 健康、canonical Pool 与 Swap Pool 一致、三个 Adapter 绑定、Bootstrap、失败回滚、普通 Rebalance、带 Swap Rebalance、allowance 清零和 Executor 余额恢复。Fork 测试通过不等于已经完成人工发布审批。

## 5. 执行部署

### 5.1 模拟部署，不广播

先确认脚本能在目标 RPC 上完成完整模拟：

```bash
forge script script/Deploy.s.sol:DeployAdaptiveLPVault \
  --rpc-url "$RPC_URL" \
  --sig 'run()' \
  -vvvv
```

由于脚本从 `DEPLOYER_PRIVATE_KEY` 读取私钥，命令不需要再传 `--private-key`。模拟阶段不会把交易发送到网络。

### 5.2 广播部署交易

确认模拟日志中的所有地址和参数正确后广播：

```bash
forge script script/Deploy.s.sol:DeployAdaptiveLPVault \
  --rpc-url "$RPC_URL" \
  --broadcast \
  --slow \
  --verify \
  -vvvv
```

如果没有配置区块浏览器验证参数，先去掉 `--verify`：

```bash
forge script script/Deploy.s.sol:DeployAdaptiveLPVault \
  --rpc-url "$RPC_URL" \
  --broadcast \
  --slow \
  -vvvv
```

部署成功后检查清单文件：

```bash
export DEPLOYMENT_FILE="deployments/${CHAIN_ID}.json"
cat "$DEPLOYMENT_FILE"
export VAULT_ADDRESS=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["vault"])' "$DEPLOYMENT_FILE")
export CONTROL_ADDRESS=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["control"])' "$DEPLOYMENT_FILE")
```

### 5.3 部署后但 Bootstrap 前的链上检查

```bash
cast call "$VAULT_ADDRESS" 'token0()(address)' --rpc-url "$RPC_URL"
cast call "$VAULT_ADDRESS" 'token1()(address)' --rpc-url "$RPC_URL"
cast call "$VAULT_ADDRESS" 'canonicalOracle()(address)' --rpc-url "$RPC_URL"
cast call "$VAULT_ADDRESS" 'vaultControl()(address)' --rpc-url "$RPC_URL"
cast call "$VAULT_ADDRESS" 'swapExecutor()(address)' --rpc-url "$RPC_URL"
cast call "$CONTROL_ADDRESS" 'vault()(address)' --rpc-url "$RPC_URL"
cast call "$CONTROL_ADDRESS" 'token0()(address)' --rpc-url "$RPC_URL"
cast call "$CONTROL_ADDRESS" 'token1()(address)' --rpc-url "$RPC_URL"
cast call "$VAULT_ADDRESS" 'initialized()(bool)' --rpc-url "$RPC_URL"
```

`initialized()` 此时必须为 `false`，且 Vault、Control、Executor、Oracle、Adapter 的地址绑定必须与 `DEPLOYMENT_FILE` 一致。

## 6. 授予角色并注册 Adapter

### 6.1 模拟配置

```bash
forge script script/Configure.s.sol:ConfigureAdaptiveLPVault \
  --rpc-url "$RPC_URL" \
  --sig 'run()' \
  -vvvv
```

### 6.2 广播配置

```bash
forge script script/Configure.s.sol:ConfigureAdaptiveLPVault \
  --rpc-url "$RPC_URL" \
  --broadcast \
  --slow \
  -vvvv
```

脚本会先使用 `ADMIN_PRIVATE_KEY` 授予三个业务角色，再使用 `MANAGER_PRIVATE_KEY` 调用三个 `configureAdapter()`。角色授予和 Adapter 配置使用不同的广播账户，适用于 Default Admin 与 Manager 分离的部署。

检查角色和 Registry：

```bash
export DEFAULT_ADMIN_ROLE=$(cast call "$CONTROL_ADDRESS" 'DEFAULT_ADMIN_ROLE()(bytes32)' --rpc-url "$RPC_URL")
export MANAGER_ROLE=$(cast call "$CONTROL_ADDRESS" 'MANAGER_ROLE()(bytes32)' --rpc-url "$RPC_URL")
export GUARDIAN_ROLE=$(cast call "$CONTROL_ADDRESS" 'GUARDIAN_ROLE()(bytes32)' --rpc-url "$RPC_URL")
export KEEPER_ROLE=$(cast call "$CONTROL_ADDRESS" 'KEEPER_ROLE()(bytes32)' --rpc-url "$RPC_URL")

cast call "$CONTROL_ADDRESS" 'hasRole(bytes32,address)(bool)' "$DEFAULT_ADMIN_ROLE" "$DEFAULT_ADMIN" --rpc-url "$RPC_URL"
cast call "$CONTROL_ADDRESS" 'hasRole(bytes32,address)(bool)' "$MANAGER_ROLE" "$MANAGER" --rpc-url "$RPC_URL"
cast call "$CONTROL_ADDRESS" 'hasRole(bytes32,address)(bool)' "$GUARDIAN_ROLE" "$GUARDIAN" --rpc-url "$RPC_URL"
cast call "$CONTROL_ADDRESS" 'hasRole(bytes32,address)(bool)' "$KEEPER_ROLE" "$KEEPER" --rpc-url "$RPC_URL"

cast call "$CONTROL_ADDRESS" 'getAdapter(uint8)(address)' 1 --rpc-url "$RPC_URL"
cast call "$CONTROL_ADDRESS" 'getAdapter(uint8)(address)' 2 --rpc-url "$RPC_URL"
cast call "$CONTROL_ADDRESS" 'getAdapter(uint8)(address)' 3 --rpc-url "$RPC_URL"
```

返回的三个 Adapter 地址必须分别等于部署清单中的 `v2Adapter`、`lowAdapter` 和 `highAdapter`。

## 7. Bootstrap 前发布门禁

### 7.1 重新执行 Oracle 健康检查

```bash
export ORACLE_ADDRESS=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["oracle"])' "$DEPLOYMENT_FILE")
cast call "$ORACLE_ADDRESS" 'isHealthy()(bool)' --rpc-url "$RPC_URL"
cast call "$ORACLE_ADDRESS" 'snapshot()((int24,int24,int24,uint256,uint256,uint256,uint256,uint32,uint32,uint32,bool))' --rpc-url "$RPC_URL"
```

`isHealthy()` 必须为 `true`。同时记录检查区块：

```bash
cast block-number --rpc-url "$RPC_URL"
```

### 7.2 检查 Bootstrap 账户余额和授权前状态

```bash
export TOKEN0=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["token0"])' "$DEPLOYMENT_FILE")
export TOKEN1=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["token1"])' "$DEPLOYMENT_FILE")

cast call "$TOKEN0" 'balanceOf(address)(uint256)' "$MANAGER" --rpc-url "$RPC_URL"
cast call "$TOKEN1" 'balanceOf(address)(uint256)' "$MANAGER" --rpc-url "$RPC_URL"
cast call "$VAULT_ADDRESS" 'initialized()(bool)' --rpc-url "$RPC_URL"
```

Bootstrap 金额必须小于等于 Manager 的两种 Token 余额，并且与审批记录、Fork 模拟和当前发布清单一致。由于 Bootstrap 不执行换币，初始金额还必须满足当前策略计划的最低部署比例；否则交易会以 `SwapRequired()` 回滚。

### 7.3 模拟 Bootstrap

```bash
forge script script/Bootstrap.s.sol:BootstrapAdaptiveLPVault \
  --rpc-url "$RPC_URL" \
  --sig 'run()' \
  -vvvv
```

### 7.4 广播 Bootstrap

```bash
forge script script/Bootstrap.s.sol:BootstrapAdaptiveLPVault \
  --rpc-url "$RPC_URL" \
  --broadcast \
  --slow \
  -vvvv
```

脚本会先把两个 Token 的 allowance 设为零，再设置为 Bootstrap 金额，然后调用 `bootstrap(amount0, amount1, receiver)`。成功后 `initialized()` 必须为 `true`；任意失败都应停止发布，不要重复对同一实例猜测性重试。

## 8. Bootstrap 后验证

```bash
cast call "$VAULT_ADDRESS" 'initialized()(bool)' --rpc-url "$RPC_URL"
cast call "$VAULT_ADDRESS" 'activeVenue()(uint8)' --rpc-url "$RPC_URL"
cast call "$VAULT_ADDRESS" 'planVersion()(uint64)' --rpc-url "$RPC_URL"
cast call "$VAULT_ADDRESS" 'lastExecutedPlan()((bytes32,uint8,uint8,int24,int24,uint64))' --rpc-url "$RPC_URL"
cast call "$VAULT_ADDRESS" 'assetSnapshot()((uint256,uint256,uint256,uint256,uint256,uint256,uint256))' --rpc-url "$RPC_URL"
cast call "$VAULT_ADDRESS" 'totalAssets()(uint256,uint256)' --rpc-url "$RPC_URL"
cast call "$TOKEN0" 'allowance(address,address)(uint256)' "$MANAGER" "$VAULT_ADDRESS" --rpc-url "$RPC_URL"
cast call "$TOKEN1" 'allowance(address,address)(uint256)' "$MANAGER" "$VAULT_ADDRESS" --rpc-url "$RPC_URL"
```

如果初始计划进入非 IDLE Venue，读取对应 Adapter 的 `snapshot()`，确认 Position、Token 顺序、Pool、Fee Tier、Tick Spacing、Vault 绑定均正确：

```bash
export V2_ADAPTER=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["v2Adapter"])' "$DEPLOYMENT_FILE")
export LOW_ADAPTER=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["lowAdapter"])' "$DEPLOYMENT_FILE")
export HIGH_ADAPTER=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["highAdapter"])' "$DEPLOYMENT_FILE")

for adapter in "$V2_ADAPTER" "$LOW_ADAPTER" "$HIGH_ADAPTER"; do
  cast call "$adapter" 'vault()(address)' --rpc-url "$RPC_URL"
  cast call "$adapter" 'token0()(address)' --rpc-url "$RPC_URL"
  cast call "$adapter" 'token1()(address)' --rpc-url "$RPC_URL"
  cast call "$adapter" 'pool()(address)' --rpc-url "$RPC_URL"
  cast call "$adapter" 'snapshot()((uint8,address,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,int24,int24))' --rpc-url "$RPC_URL"
done
```

最后保存：源码提交、`forge build` 输出、所有广播交易哈希、部署区块、部署清单、角色读取结果、Adapter 读取结果、Oracle 快照、Bootstrap 参数、Bootstrap 事件和区块浏览器验证结果。只有所有读取结果与输入一致时，才可以把部署状态标记为完成并开放 Deposit。

## 9. 回滚和重新部署

- 部署或 Configure 阶段失败：保留失败交易哈希和错误数据，废弃未初始化实例，修正输入后重新执行。
- Bootstrap 前发现参数错误：不要发送 Bootstrap，修正未冻结的链下配置或重新部署实例。
- Bootstrap 失败：记录回滚原因和当前区块，再从第 7 节重新执行所有门禁；不要只修改命令中的一个金额后跳过 Oracle 和角色检查。
- Bootstrap 后发现 immutable 地址或绑定错误：不要开放 Deposit；按审批后的新 Vault 实例和迁移方案处置。
- 任何私钥、RPC 凭据或未审计配置进入日志、Git 或部署清单时，应立即停止发布并按密钥泄露流程处理。
