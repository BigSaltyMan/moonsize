# 大模块分析基准

先记录可重跑的数据，再决定是否优化。首版仅增加 Node 内置模块脚本、CI smoke
和文档；没有修改分析算法、公开 API、CLI 参数或退出码，也未实现数据段明细。

## 运行

```sh
moon build --target native --release
CLI=_build/native/release/build/cmd/main/main.exe
node scripts/bench-large-modules.mjs "$CLI" --smoke
node scripts/bench-large-modules.mjs "$CLI"
node scripts/bench-large-modules.mjs "$CLI" --large
```

有已确认来源的当前 release CLI 可直接复用，无需重复构建。`--timeout-ms N`
配置每次分析超时，默认 30000 ms。脚本自身参数不传给分析器。

默认不会把任意二进制标成工作区 HEAD；`cli.source_commit` 为 null，工作区提交
单独记录。只有确认构建来源后才显式声明，例如在成功构建、分析源码无本地修改后：

```sh
node scripts/bench-large-modules.mjs "$CLI" --cli-source-sha "$(git rev-parse HEAD)"
```

该参数是**调用者声明**，脚本不独立证明源码和二进制的对应关系；它始终记录实际
CLI SHA-256。CI 在同一 checkout 构建后声明 GITHUB_SHA，保留该 SHA 的运行证据。
外部 CLI 的来源未知时请省略，不用当前仓库 SHA 冒充。

## 少量代表输入

| 模式 | 样本 |
| --- | --- |
| smoke | 64 函数二叉调用树；9 函数、8 调用点、8 个静态候选的间接调用模块。各执行一次，无预热。 |
| 默认 | 1000 / 10000 函数的同结构稀疏二叉调用树；129 函数、256 个重复间接调用点、128 个候选；仓库 fib.wasm。 |
| large | 在默认样本之后追加同结构 50000 函数档位，仅供手动运行。首版本机没有执行这一档。 |

二叉树从导出函数0开始，每个非叶子最多调用两个子函数，全部本地函数可达；
不使用名称或数据段。间接模块导出 caller 0，私有 table 以 active element
初始化，所有候选使用同一个 void 签名，无运行时写表。候选展开预先限制在
32768 条来源边记录以内；不使用极端矩阵探测 OOM。

合成输入按固定参数确定性生成，再次生成核对 SHA-256，并经 V8 独立验证。
一个小型受限检查器从**实际编码**复核本地函数、call/call_indirect 和静态候选，
不尝试实现通用 Wasm 解码器。输出中：

- `expected_source_edge_records`：预计逐调用点展开的来源记录数。默认间接样本是
  256 × 128 = 32768；这是预计的分析器建边记录数量。
- `fixture_unique_adjacencies`：从合成输入指令及静态候选去重得到的 caller/callee
  关系。该间接样本只有128个，不能把32768写成唯一邻接边数。
- `analyzer_unique_adjacencies`：首版未额外导出分析器图，保留 null。前一字段不是
  实际 CLI 图导出计数。smoke 保持每个输入仅一次真实 CLI 调用。

fib 是项目已有的小型 MoonBit 产物，记录47个本地函数、1个导入函数；首版不另造
通用指令扫描器，其调用点、table候选及边数字段明确为 null。它不代表真实大型
项目覆盖。合成输入的可控规模也不代表所有 Wasm 图形态。

## 时间与结果契约

默认每组一次预热、三次正式测量，仅在10000函数样本追加一组 `--retained`。
其他命令均为普通文本报告，使用默认 Top 10，没有压缩/HTML/图导出组合矩阵。
预热原始记录保留，但不参与统计。每组保留正式毫秒值、中位数、最小值和最大值；
失败或缺少正式记录时统计为 null，不能过滤失败后宣称全部成功。

单调时钟 `process.hrtime.bigint()` 从启动子进程前计到进程关闭，包含启动、
读取、分析及文本输出。每次 stdout/stderr 采用同一方式写入新日志文件，避免
终端打印干扰；不代表 fsync 后的持久化时间。输入生成、再次生成和V8/数量检查
分别记录，不混入 CLI 时间。未加入内部阶段计时，**峰值内存未测量**。

普通 `analyze` 已无条件计算 retained；plain 与 retained 组都包含该计算，二者
差值不能叫作“支配树计算时间”，还包含报告处理、启动噪声和运行波动。

超时只对本次 `spawn` 得到的子进程句柄发送 SIGKILL，不按名称杀进程，不改分析器
资源参数。记录 input-validation-failed、spawn-failed、unexpected-exit、timeout
或成功，另区分正常退出却与预期函数数不符的 unexpected-output。失败保留已有
输入/日志/运行记录，给出简短摘要并返回1；参数错误返回2。一组第一次失败后停止
重复该组，避免连续触发同样超时；其他样本仍记录结果。

每次同时进行两个很小的受控检查：计时器子进程超时后已终止；不存在的程序被
归为启动失败。它们不是 CLI 性能样本。真实测量顺带验证 CLI 报告中的本地函数
数，正式运行记录可直接重算统计；不另建测试矩阵或 MoonBit 单元测试。

## 本地一次默认测量 · 2026-10-20

Windows 10.0.26300 x64，AMD Ryzen 9 8940HX（32个逻辑CPU），Node24.18.0 /
V8 13.6.233.17-node.50，moon0.1.20260915 / moonc v0.10.13+cbb11c36f。
分析源码为 `0cadc6be7638786a6520eb482d4bd9b2dccc6b7d`，本次成功执行一次 native
release 构建后测量；分析源码无本地修改。实际二进制SHA-256：

`f341117d4deae7de5087e454d3a71365e5cbc8d26d21cd5b9749030e6a277215`

| 样本 / 普通或retained报告 | 输入B | 正式原始时间 ms | 最小 / 中位 / 最大 ms |
| --- | ---: | --- | --- |
| tree-1000 / plain | 6903 | 31.3007, 30.9541, 29.4670 | 29.4670 / 30.9541 / 31.3007 |
| tree-10000 / plain | 69904 | 72.4528, 67.7227, 67.8865 | 67.7227 / 67.8865 / 72.4528 |
| tree-10000 / retained | 69904 | 81.6780, 83.2089, 92.0882 | 81.6780 / 83.2089 / 92.0882 |
| indirect-repeated / plain | 1976 | 37.7880, 39.0961, 35.1233 | 35.1233 / 37.7880 / 39.0961 |
| fib / plain | 10675 | 31.1143, 35.3011, 33.2310 | 31.1143 / 33.2310 / 35.3011 |

| 输入 | SHA-256 |
| --- | --- |
| tree-1000 | `9566cd117c34eecbef0098e05ad466fd3dee995a37aed16967fdc913f43d0672` |
| tree-10000 | `b8f7b56487caf689861d199f13722c6e6a07df5883e6d949ac2d9358a8585b9f` |
| indirect-repeated | `05be7e7e890d822fc96bf1b603407a3675fa57ce77ab5031bc0da6b0de9216f0` |
| fib | `0e6f10e56434b67adb162cdb56a46553ef38b8de1abd0d0deb1fe56d7173d10c` |

本次四个样本、五组命令全部成功，无分析超时或非预期退出。1k到10k函数的
这组稀疏树样本耗时增加，但未出现需要立即优化的明显瓶颈；不能据此给出通用
复杂度或跨平台速度结论。受控候选展开也未出现失败。暂不据此修改 retained
计算或引入 table 候选缓存。名称、其他图形态、真实大型项目、峰值内存以及50k
档位均未覆盖；没有预设性能提升百分比。

## 原始证据与CI

每次创建 `_build/large-module-benchmark/run-*/` 新目录，保留 `inputs/`、`logs/`、
`results.json` 和 `summary.md`。不会复用旧运行目录或删除旧报告。results保存
完整命令、工作目录、CLI/输入/脚本哈希、工具链、CPU、运行次数、退出状态和原始
毫秒值，进行中会更新本次运行自己的结果文件，不改以前运行的证据。

上述默认数据来自本机 `run-4kyAei`；定向 smoke 为 `run-8A18Qv`，两组日志与
结果均保留在本地构建目录，统计已从保存的正式原始记录独立重算核对。它们是
提交前的本地记录，不冒充目标提交的干净CI记录。可用本文参数、输入哈希和命令
复现，其他机器的实际数值以新的原始记录为准。

现有 Linux CI 只追加一次 smoke，复用Node24和已经构建的native release，上传
`large-module-benchmark-smoke` 小型artifact；不运行默认/large，不设共享runner
毫秒门槛，也不增加第二个完整测试job。现有完整回归仍由原CI完成。

性能成功不证明分析模型完整；retained不是重编译减量，独立gzip不可相加。
数据段明细属于后续功能，不在本次交付中。
