# 函数反向引用查询

本功能是公开 0.5.1 之后的源码增量；本次不改版本、不发布 Mooncakes。请从当前
源码构建 native CLI。它列出目标在当前引用模型中的全部已记录一跳函数体来源，
不调用 analyze，不计算 retained，不递归展开或运行路径 BFS。

```sh
moonsize app.wasm --callers 42
moonsize app.wasm --callers 42 --top 20
moonsize app.wasm --callers 42 --callers-json new-callers.json
moonsize app.wasm --callers 42 --strict
```

只允许搭配 Top、callers JSON 和 strict；与其他分析/输出模式组合，在读取输入前
报参数错误。目标索引包含前置导入函数，不是本地函数编号。合法整数超出模块索引
范围是输入错误；负数、小数或整数溢出是参数错误。

`--why-index` 解释从模型根到目标的一条最短路径；`--callers` 列出全部已记录一跳
来源。两者都不是执行轨迹。引用者本身可能不可达，查询不会据此过滤它们。

## 来源和计数

- Direct：实际 `call` 或 `return_call` 指令。
- Reference：实际 `ref.func`，表示取引用，不能当作直接调用。
- Indirect：实际 `call_indirect` 或 `return_call_indirect` 的静态保守候选。

来源来自带位置的 graph.edges，每条保留 caller、callee、kind、实际 opcode、
原文件偏移，以及适用的 type/table 索引。查询只为命中来源恢复指令证据，每个
命中偏移最多解码一次。相同引用者的不同位置全部保留，完全相同的来源去重。
顺序固定为引用者索引、文件偏移、Direct/Reference/Indirect；不按名称合并。

唯一引用者数量与来源指令数量分别统计。文本 Top 限制引用者组数，不截断组内
位置、完整汇总或 JSON；也不限制此前解析与建图成本。库结果不截断。

导出、start 和 element 根不是函数体调用点，不虚构 caller=-1 或 opcode；需要
解释根来源时使用 `--why-index`。导入目标没有本地 body，encoded_size 为 null。
无来源正常返回空数组，并明确说明这不能证明函数未使用或可删除。

模块级图诊断完整保留，但不一定与当前目标有关。未建模的 call_ref 不会被猜成
某个目标的调用行；它前面的 ref.func 则仍是独立的取引用证据。
graph_complete=true 也不证明完整 Wasm 语义、真实执行或删除/重编译/gzip 收益。

## 实测样本

`scripts/test-function-callers.mjs` 构造一个 136 字节合法模块，V8 独立验证一次。
输入 SHA-256：`09fda5d60dd66be7be2b99f2ce1ae6f757f5001709f642b0213935adaf4e295a`。
查询导入目标 #0，实测 3 个引用者、7 处来源。#1 和 #2 同名，仍分别记录；它们
不因缺少根路径而被过滤。#4 自引用；#5 是导出根但没有入向函数体来源。

| CALLER | KIND | OPCODE | FILE OFFSET | TYPE | TABLE |
| --- | --- | --- | ---: | ---: | ---: |
| 1 | direct | call | 62 | — | — |
| 1 | reference | ref.func | 64 | — | — |
| 1 | indirect candidate | call_indirect | 69 | 0 | 0 |
| 1 | direct | call | 72 | — | — |
| 2 | direct | return_call | 77 | — | — |
| 3 | reference | ref.func | 82 | — | — |
| 3 | indirect candidate | return_call_indirect | 88 | 0 | 0 |

Top1 文本仅显示 #1 的四行，仍报告 3/7 完整计数；JSON 保留全部七行。function3
在文件偏移84的 call_ref 产生模块级诊断，未生成猜测目标行。strict 返回3且不
创建 JSON；非严格 JSON 新建成功，已有目标返回1且原字节不变。
原始本地结果：`_build/function-callers-verification/run-xgOrRB/`；该路径是本地
证据身份，不是公开下载入口。CI 使用同一脚本重新生成，不硬编码本地路径。

## API 和格式

```moonbit
function_callers(Bytes, Int) -> Result[FunctionCallersReport, FunctionCallersError]
render_function_callers(FunctionCallersReport, Int) -> String
render_function_callers_json(FunctionCallersReport) -> String
describe_function_callers_error(FunctionCallersError) -> String
```

`FunctionCallersReport` 包含目标 FunctionPathNode、file_size、实际 sha256、
完整 callers 分组、caller_count、source_count、graph_complete、diagnostics、
graph_warning 和 modeling_scope。`FunctionCallerGroup` 含 caller 节点与全部
FunctionPathStep 来源。复用已有节点/证据类型，不修改路径报告及其格式。

错误只有 `CallersInputError(WasmError)`、`InvalidCallersTarget(index,count)`、
`InvalidCallersEvidence(file_offset,reason)`。Options 新增 callers_index 和
callers_json，默认均为 None；迁移详见[接口增量说明](migration-0.5.md)。

JSON 独立使用 `format: moonsize-function-callers`、`schema_version: 1`。
来源的 `file_offset` 是文件位置，不是内存地址；`candidate` 只对间接边为 true。
指令不适用的 type_index/table_index 和导入节点的 encoded_size 都是 null。
既有路径、图和 HTML 格式不变。

退出码：0 成功（包括空结果），1 读取/解析/目标/证据/输出错误，2 参数错误，
3 strict 拒绝不完整图。JSON 必须使用新 .json 目标，统一预检与独占创建；strict
检查先于文件检查。沿用既有多输出非事务边界，不引入新的写入通道。

本地仅运行新文件内的三个组合测试及四个新功能 CLI 场景；类型检查、接口生成
和构建不等于运行旧测试。旧回归只由既有目标 Linux CI 自动执行。本功能不增加
HTML、递归查询、限额体系、源码演示或性能基准。

## 与单函数calls查询的区别（0.5.1后源码增量）

`--callers`查当前模型的入向引用，可能包含ref.func取引用和间接候选；
`--calls <index>`只解码目标本地body，列出其中实际编码的六种调用指令，
排除ref.func，直接目标可核对，动态目标为null。不构图、不递归、不按可达性
过滤，因此二者不是简单的图反转。calls不提供graph_complete、unresolved_count
或strict保证。Top仅限制调用行，JSON始终完整；导入目标没有本地body，明确
拒绝，不伪造空清单。[单函数调用清单与实际记录](function-calls.md)。
