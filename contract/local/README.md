# 本地部署与交易模拟

本目录集中保存本地 Anvil 环境的部署脚本、工具、模拟器、测试和使用说明。正式业务合约仍在 `../src/`，正式部署、配置和初始注资脚本仍在 `../script/`；本地流程直接复用，不另写一套业务部署逻辑。账户、测试资产和参数仅供本地演示，不得用于真实资金。

## 文件职责

- `script/`：`LocalToken.sol` 测试资产、`PrepareLocal.s.sol` 协议环境准备、`PreviewLocalBootstrap.s.sol` 初始注资数量预览。
- `tools/deploy-local.ts`：本地部署入口，组织 Foundry 阶段、预热真实节点、校验结果及发布清单。
- `tools/local-deployment.ts`：参数、阶段顺序、清单校验与文件发布辅助；`tools/local.ts` 提供本地账户、RPC 和合约读取工具。
- `simulator/`：真实多池交易与平稳、趋势、冲击、恢复场景。
- `test/DeploymentScript.t.sol`：四项部署脚本回归，覆盖文本库链接、多处引用、缺失占位符和已部署策略库调用方式。
- `tools/*.test.ts`、`simulator/*.test.ts`：本地工具单元测试；`tools/deployment-check.ts`、`tools/e2e.ts`、`tools/market-check.ts`：真实部署、浏览器与行情验收。
- `deployments/`、`broadcast/`、`.state/`：运行时生成的清单、阶段日志、广播记录和进程锁，均被 Git 忽略。

Foundry 和 npm 继续使用现有 `contract/` 工作区配置。本地环境与合约集成测试共用的官方 Uniswap 依赖保留在 `../lib/uniswap-test-deps/`。通用 ABI 导出工具保留在 `../tools/export-abi.ts`。前端仍读取 `frontend/src/generated/deployment.json`，该文件是生成的公开配置，不包含私钥。

## 1. 环境与启动

以下 npm 命令均在仓库根目录执行，需要 Node.js 24、npm 11 和 Foundry（验证版本 1.5.1）。

```bash
git submodule update --init --recursive
npm ci
npm ci --prefix contract/lib/uniswap-test-deps --ignore-scripts --no-audit --no-fund
npm run abi
```

分别在不同终端运行 `npm run chain`、`npm run local:deploy`；部署完成后启动 `npm run dev`，需要持续交易时另开终端运行 `npm run market -- --scenario steady`。

- Anvil：chain ID `31337`，HTTP `http://127.0.0.1:8545`，每秒出块；前端：`http://127.0.0.1:5173`。
- 资产：`tUSD`（6 位精度）与 `tETH`（18 位精度），每个开发账户各获得一亿枚完整测试代币，初始价格为 1:1 测试单位。`tETH` 不是 Wrapped ETH，不支持真实原生币包装，也不测试仓位 NFT 的元数据展示。
- 协议：官方固定版本 Uniswap V2 Core / Router02、V3 Core / Periphery；V2 和 V3 500 / 3000 / 10000 池各有约一百万完整代币背景流动性，V3 使用全区间。
- 预言机和换币执行绑定 V3 10000 池；长窗口 120 秒，短窗口 20 秒。策略进入中／高／极端偏离阈值为 30 / 100 / 300 基点，冷却 15 秒，均非生产建议。

### 部署阶段

入口 `local/tools/deploy-local.ts` 在 `contract/` 工作区依次执行：

1. 广播 `local/script/PrepareLocal.s.sol`，部署测试资产和官方协议、建池、扩容观察记录并添加背景流动性。
2. 等待上述广播确认后，通过真实 Anvil RPC 推进 121 秒并出块。模拟中的 `vm.warp()` 无法替代真实节点预热。
3. 广播原有 `script/Deploy.s.sol`，部署策略库、组件工厂、预言机、Vault 和适配器。
4. 广播原有 `script/Configure.s.sol`，以根管理员和 Manager 配置角色与适配器。
5. 只读执行 `local/script/PreviewLocalBootstrap.s.sol`，调用已部署策略库和适配器计算初始双资产数量，不重写策略公式。
6. 默认广播原有 `script/Bootstrap.s.sol`，Manager 进行两种代币授权并初始注资。

广播使用 `forge script --broadcast --slow`，保留模拟检查。TypeScript 只处理参数、节点检查、阶段调用、预热、结果校验和文件衔接，不直接部署或配置合约。公开开发私钥只通过子进程环境传入，日志会再次脱敏；部署不使用 `mockCall`、`prank` 或余额存储覆盖。

## 2. 钱包与角色

使用 Anvil 默认公开测试助记词对应的七个账户。启动 Anvil 时会打印私钥，请使用独立开发钱包导入，严禁向这些账户转入真实资产。

- `0` deployer：`0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266`。
- `1` admin：`0x70997970C51812dc3A010C7d01b50e0d17dc79C8`。
- `2` manager：`0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC`。
- `3` guardian：`0x90F79bf6EB2c4f870365E785982E1f101E93b906`。
- `4` keeper：`0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65`。
- `5` user：`0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc`。
- `6` trader：`0x976EA74026E726554dB657fA54763abd0C3a0aa9`，无业务角色，供模拟器独立发送交易。

默认初始份额归 Manager，用户通过存款获得份额。原生 Gas 余额由 Anvil 提供，代币排列以合约 `token0/token1` 为准。根管理员只管理角色；Guardian 只能新增暂停和禁用适配器，恢复需要 Manager。正常赎回不受三个暂停开关限制。

## 3. 初始化前模式与重复部署

```bash
npm run local:deploy -- --uninitialized
```

此模式仍完成部署、预热、角色配置和数量预览，仅跳过初始注资。连接 Manager 钱包进入“运行管理”，审核双资产金额后执行初始化，浏览器依次请求两次授权和一次 Bootstrap。

已使用的部署账户默认拒绝再次部署。需要在同一链创建另一组独立实例时，显式传入 `--reset-confirmed`；它不重置链、不删除旧合约，只更新公开清单。两项参数可组合使用。

## 4. 持续交易

```bash
npm run market -- --scenario steady
npm run market -- --scenario trend --seed 42
npm run market -- --scenario shock
npm run market -- --scenario shock --shock-ticks -1200
npm run market -- --scenario recovery
npm run market -- --scenario steady --seed 42 --rounds 10 --interval 1000 --scale 1 --bias 0
```

每轮依次交易 V2、低费率 V3、高费率 V3 和预言机池，围绕共同目标价确定方向，并按储备／流动性估算规模。使用真实 Router 模拟报价设置最低输出；输出金额从确认回执的 Token `Transfer` 事件取得，不把模拟报价当作实际成交。

参数：`--scenario` 取 `steady` / `trend` / `shock` / `recovery`；`--seed` 为非负安全整数，默认 42；`--rounds` 为 0–100000，0 表示持续；`--interval` 为 500–60000 毫秒，默认 3000；`--scale` 为 `(0, 2]`，默认 1；`--bias` 为 -100–100 Tick，默认 0。实际轮次还包含交易确认等待。

`--shock-ticks` 仅适用于 `shock`，接受绝对值为 1–5000 的整数，默认 `1200`。运行约 10 秒后，目标 Tick 相对初始 1:1 报价移动指定值并保持。默认 `1200` 让 `tETH` 相对 `tUSD` 跌价；`-1200` 让 `tETH` 相对 `tUSD` 涨约 12.7%。

同一随机种子和同一链上时间输入产生相同目标，但实际出块时序会影响成交结果，并非逐字节确定重放。恢复场景先保持冲击，再逐步回归。场景稳定后长短时间加权平均价格会收敛，偏离不会永久维持。

输出逐行 JSON：`started`、`swap`、`market`、`error`、`stopped`。金额使用 `bigint`；浮点 Tick 估算仅决定本地交易方向和规模。模拟器不会调用 Vault 初始化、存款、赎回或再平衡，也不自动修改链时间。锁位于 `contract/local/.state/market.lock`；第二个进程拒绝启动，连续失败三次后退出。

## 5. 手动联调

用户在“我的资产”填写两种最大投入，分别授权、预览并确认存款。启动模拟器后在总览观察真实价格、偏离与 V3 待领取费用；V2 费用已包含在储备权益，口径不同。

在“策略再平衡”刷新计划：无需换币时任何账户可执行；需要换币时切换 Keeper / Manager。可点击“计算建议金额”，按当前计划试算并只读模拟若干候选，再点击“填入建议金额”。建议不会改动“调用者最低输出”、签名或发送交易；它不保证最优或实际成交。计划或最低输出变化后须重新计算；找不到可执行金额时仍可手动填写。提交时还会重新检查计划并模拟整笔交易。

前端每笔写链交易都会重新估算 Gas，增加 20% 余量并向上取整，再使用同一 Gas 上限模拟和提交。估算或模拟失败时不会打开钱包确认；初始化等多笔交易逐笔估算。该余量不改变 Gas 单价，也不影响只读查询或预览。

合约基于历史状态和同一预言机快照连续计算至最终状态，可双向跨级但只执行最终计划；实时偏离、候选计划和已执行状态不等价。剧烈行情可能让计划过期或仓位单边，按合约错误处理；策略撤至 EXTREME/IDLE 豁免冷却，重新入场及其他迁移仍受冷却限制，滑点和迁移校验保持有效。没有自动提交的 Keeper。

Guardian 可测试暂停和紧急退出，Manager 恢复；用户仍可预览和执行正常赎回。

## 6. 文件、失败与恢复

公开清单：`contract/local/deployments/local.json` 和 `frontend/src/generated/deployment.json`，包括地址、部署区块、公开账户及初始化数量，不含私钥，均被 Git 忽略。已有清单随目录迁移保留，无需因搬目录重新部署。

每次运行的中间清单和脱敏日志位于 `contract/local/deployments/.local-*/`。只有全部必要广播成功，且链上代码、绑定、角色、预言机、账户资金和初始化状态校验通过，才发布最终清单。Foundry 模拟也会写 JSON，因此文件存在不代表部署成功。

阶段失败立即停止，不自动整套重试、不回滚已广播交易。检查日志后可重启干净 Anvil 再部署；保留同链旧实例时，审核后用 `--reset-confirmed` 创建新实例。发布通过逐个临时文件替换，普通失败会尝试恢复旧文件；两份文件不是跨文件原子事务，强杀或掉电后应检查一致性。

- `Ctrl+C` 停止模拟器，等待当前已发送交易处理，链与前端继续运行。
- RPC 故障或余额不足时停止模拟器并检查环境；进程不会无限铸币补充。
- 残留锁会检查旧 PID，已退出则自动清理；PID 仍存在时先确认进程。
- Anvil 重置后停止模拟器、重新部署并刷新浏览器；旧区块哈希或代码校验不通过时拒绝继续。
- 自定义端口时，工具的 `LOCAL_RPC_URL` 与前端的 `VITE_RPC_URL` 必须指向同一回环 Anvil。
- 前端配置保留原生成路径；接口变化后运行 `npm run abi` 更新可提交的 ABI。

## 7. 验收

```bash
npm run lint
npm run format:check
npm test
npm run build
npx playwright install chromium
# 四项 Solidity 部署脚本测试及独立临时 Anvil 真实部署回归
npm run test:deployment
# 额外启动临时前端，执行默认/初始化浏览器流程和真实行情冲击
npm run test:deployment -- --browser
# 已启动本地链、部署及前端，且停止其他交易进程时使用
npm run test:e2e
npm run test:e2e -- --bootstrap
npm run test:market
# 可选：shock 稳定、同池调整计划需要 tETH → tUSD 时，仅验证建议金额，不发送交易
VITE_TEST_LOCAL_SWAP=1 npm test -w frontend -- local-suggestion-check.test.ts
```

单独运行本地 Solidity 测试：在 `contract/` 执行 `FOUNDRY_TEST=local/test forge test`；格式检查执行 `forge fmt --check local/script local/test`。原有合约回归继续使用 `npm run contract:test`，本地专用测试与原 `test/` 分开。

独立验收自动选择空闲回环端口，不重置开发者已有链；会临时替换两份清单，结束后恢复并关闭自己启动的服务。禁止与部署、人工前端操作或其他交易进程并行。正常退出或抛错会清理恢复，强杀不保证执行清理。

临时前端使用 `deployment-test` 模式关闭热更新，避免切换清单重建钱包配置而触发账户身份保护。手动 `test:e2e -- --bootstrap` 建议先停普通前端，再运行 `npm run dev -w frontend -- --mode deployment-test`，保留账户和网络身份检查。

浏览器测试钱包只在 Node 验收程序内注入，通过 Anvil 解锁测试账户真实发交易，不进入前端发布产物。测试覆盖授权、存款、多池 Swap、费用增长、赎回、再平衡、角色授撤、暂停和紧急退出；结束后恢复链快照，期间人工交易也会被快照恢复丢弃。本地通过不代表主网发布验收或安全审计完成。
