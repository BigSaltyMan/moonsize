# 优化实验报告

`--experiment` 把两份真实 Wasm 产物的测量、函数归因、构建条件与业务验证记录放在一份报告中。HTML 可离线打开，JSON 便于 CI 保存或读取。核心实现位于 MoonBit 库，Node 脚本只负责案例构建与回归检查。

## 使用流程

1. 固定工具链、target、优化模式、strip 和 feature 设置，保存修改前的构建产物。
2. 根据函数排名、引用关系或业务需求修改源码，运行项目自身的回归检查，保存修改后的构建产物。明确哪些行为应保留，哪些功能有意移除。
3. 填写实验说明，生成报告，检查实际文件和整文件 gzip 的变化。必要时回退源码重新构建，确认基线可复现。

```sh
moon build --target native --release
# 两个输入已经由自己的项目构建；本命令不会执行说明文件中的命令。
./_build/native/release/build/cmd/main/main.exe after.wasm \
  --baseline before.wasm --experiment experiment.html \
  --experiment-context context.json --top 20

# JSON 和 HTML 是同一份数据的两种表示，输出文件均须为新路径。
./_build/native/release/build/cmd/main/main.exe after.wasm \
  --baseline before.wasm --experiment experiment.json \
  --experiment-context context.json --max-size 0B
```

也可以省略 `--experiment-context`，说明文件中的 JSON `null` 同样表示未提供说明；此时构建可比性与业务验证均显示 `not-recorded`，不会自动补成通过。报告路径支持小写 `.html`、`.json` 后缀，且不能与 `--html`、`--call-graph`、`--retained`、`--dead-code`、`--compress`、`--diff-functions` 合用。实验模式已经包含整文件 gzip 和函数/包级差异，保留 `--top`、`--strict`、`--max-size` 的用途。

## 实验说明格式

```json
{
  "title": "移除可选日志分支",
  "hypothesis": "保留计算结果，有意移除调试输出；检查重新构建后的实际减量",
  "baseline": {
    "revision": "修改前源码提交或源码 SHA-256",
    "command": "moon build --target wasm --release --no-strip",
    "toolchain": "填写实际 moon version --all 结果",
    "target": "wasm",
    "mode": "release",
    "strip": false,
    "features": []
  },
  "current": {
    "revision": "修改后源码提交或源码 SHA-256",
    "command": "moon build --target wasm --release --no-strip",
    "toolchain": "填写实际 moon version --all 结果",
    "target": "wasm",
    "mode": "release",
    "strip": false,
    "features": []
  },
  "validation": {
    "status": "passed",
    "command": "填写实际执行的项目回归命令",
    "notes": "记录应保留的行为、通过的检查及原始日志位置；不等同完整行为等价证明"
  }
}
```

提供说明时，上述字段必须齐全；未知字段、错误类型和无效状态会在读取 Wasm 前报错。`validation.status` 支持 `passed`、`failed`、`not-run`；前两者须填写非空命令，`not-run` 的命令可为空。revision、command、toolchain、target、mode 和标题、假设必须是非空字符串；`strip` 必须是布尔值，`features` 是非空字符串组成的数组，可使用空数组。

说明是**调用者声明**。工具不执行其中的命令，不验证声明与文件之间的源码关系，不把 `passed` 冒充为自己执行过的测试。两侧的 command、toolchain、target、mode、strip、features 按原样比较，任一不同会列入 `different_build_fields`；一致仅标为 `same-declared-settings`，并不证明所有环境条件相同。revision 可以不同，features 顺序不同也会被保守地提示。

## 如何读报告

- `raw_delta` 和 `whole_gzip_delta` 统一为 **current − baseline**；负数表示减少。整文件 gzip 分别压缩完整输入，不累加局部 gzip。压缩失败保留 `null` 和具体原因，不用原始大小冒充。
- 两侧记录实际输入字节的 SHA-256、路径、文件大小、gzip 结果及图诊断。SHA-256 标识产物内容，不证明其源码或业务正确性。
- 段差异覆盖完整编码，同名 custom 段汇总；函数/包差异使用已有唯一原始符号匹配与尽力包归因。缺名和重复名称仍保留为未匹配类别。
- `functions`、`packages` 是按绝对变化排序的前 N 条，`function_record_count`、`package_record_count` 记录完整条数。`matching` 与 `baseline_code`、`current_code` 保留完整覆盖率和 code 开销，`--top 0` 不会把完整汇总归零。
- HTML 同样展示声明条件、验证状态、测量边界和图诊断。文件变小、两侧配置相同、strict 通过，都不会被解释为完整行为等价或某个函数的精确删除收益。整文件 gzip 也不是实际 HTTP/TLS 网络成本测量。
- JSON 格式使用 `schema_version: 1`。CLI 额外写入 `raw_growth_budget_bytes`（未设置则为 null）、`raw_growth_budget_passed`。库接口只负责实验测量，不执行 CLI 预算。

退出码：`0` 表示报告生成且预算通过，**不代表业务验证通过**；`1` 表示输入、说明、解析或输出错误；`2` 表示参数错误；`3` 表示原始文件增长超预算或 strict 发现任一侧调用图不完整。预算拒绝仍生成解释结果的报告；strict 拒绝不创建报告。所有已存在的输出路径均被拒绝，避免覆盖输入或已有证据。

## 可复现案例与测试

```sh
node scripts/test-optimization-experiment.mjs
node scripts/demo-retained-boundaries.mjs
```

第二条命令实际构建独占分支和共享依赖的 debug/release 源码对照，执行保留行为检查及回退核对，再通过 CLI 为每个案例输出 `experiment-context.json`、`experiment.json` 和 `experiment.html`。另有明确标为人工编码的 table 对照。产物位于 `_build/retained-boundaries/<案例>/`，CI 的 `retained-boundary-evidence` 产物包含原始 Wasm、输出、实验说明及报告。

仓库中的 [HTML 示例](../examples/optimization-experiment.html) 与 [JSON 示例](../examples/optimization-experiment.json) 来自 `unique-debug` 案例：文件 10824 → 10168 B，整文件 gzip 5236 → 4999 B。这是指定工具链的一次实测快照，其他工具链应重新构建、以新结果为准。源码和模型边界见 [retained size 实测案例](retained-size-boundaries.md)。

## 库接口

```moonbit
match @moonsize.experiment_report(before, after, "before.wasm", "after.wasm", context, top=20) {
  Ok(report) => {
    println(report.stringify(indent=2))
    let html = @moonsize.render_experiment_html(report)
    // 将 html 交给应用自身的输出层保存。
    ignore(html)
  }
  Err(reason) => println(reason)
}
```

`check_experiment_context(context)` 可单独预检查；`Json::null()` 表示未提供说明。`experiment_report` 返回 `Result[Json, String]`，错误保留 baseline/current 侧别。新增三个公开函数和 Options 的两个可读字段，现有比较 API 的签名不变。
