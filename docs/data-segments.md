# Wasm 数据段编码明细

本功能是 0.4.0 发布后的源码更新，尚未发布到 Mooncakes；请从当前源码构建
native CLI。它解释 data 段中哪些文件字节属于初始化 payload，哪些属于编码元数据。
不推断源码归属，不把文件字节视为运行时内存占用，也不预测删除后的重编译收益。

## 使用

```sh
moon build --target native --release
CLI=_build/native/release/build/cmd/main/main.exe
"$CLI" app.wasm --data-segments
"$CLI" app.wasm --data-segments --top 20
"$CLI" app.wasm --data-json new-data.json
```

`--data-json` 隐含启用文本明细，要求新的 `.json` 文件。未启用这两个选项时，
默认报告不变。文本复用 `--top`（默认10），按 payload 长度降序、原始序号升序
排列；Top 只限制显示，汇总包含全部条目，JSON 按原始序号保留全部条目。

可组合普通文本、`--retained`、`--dead-code`、`--compress`、`--strict`、
`--max-size` 和 `--baseline`。baseline 仍只执行原有比较，不比较数据条目。
暂不与 HTML、调用图导出、experiment、函数路径、budget 或 `--diff-functions`
组合；参数阶段拒绝这些组合并返回2，在读取输入前报错。

解析错误、输出保护或写入失败返回1。解析在正常输出前完成；strict 仍在目标
预检查和写入前拒绝不完整图并返回3。原有 max-size 行为不变，超限仍可保存明细
后返回3。新 JSON 使用统一预检查及原生独占创建，不删除已有目标。这不提供
多文件事务；后续失败可能留下之前的新文件或本次新建的部分文件。

## 编码和范围

按 [Core Wasm data/data count 编码](https://webassembly.github.io/spec/core/binary/modules.html#data-section)
读取模式0（隐式 memory 0 的 active）、1（passive）、2（显式 memory 索引的
active），复用有界 Reader 和受检查的整数转换。保留合法非最短 LEB 的实际长度。
data 和 datacount 各自必须完整消费；datacount 如存在，须等于实际 data 条目数，
data 缺失时实际条目数是零。datacount 是独立段，不计入 data 段账本。

每个范围为 `[file_offset, file_offset + size)`。表达式通过现有指令解码器逐条
读取，包含最后的 `end`；不会把立即数中的 `0x0b` 当成表达式结束。

- active：`memory_index` 和表达式范围有值，`offset_status = not_evaluated`。
- passive：`memory_index` 和表达式范围为 null，`offset_status = not_applicable`。
- 未知指令、截断和解码错误返回错误，不替换成零；不输出求值后的内存偏移。

这是结构检查，尚未完成类型验证、常量表达式合法性验证、memory 索引存在性
或实例化边界检查。复用的解码器所不支持的表达式编码会明确返回错误。

## 字节账本

```text
data 段完整大小 = 段头大小 + 数量字段大小 + sum(条目完整编码大小)
条目完整编码大小 = 模式字段 + 可选 memory 索引 + 可选表达式
                 + payload 长度字段 + payload 字节数
```

条目元数据是条目完整编码减去 payload；段级开销是段头加数量字段。全部采用
实际编码宽度。无 data 段时 `present=false`、段位置为 null、各大小为零；存在
空段仍有段头和零数量字段；payload 为空的条目仍有模式等元数据，三者不混淆。

## 本次实际样本

`node scripts/test-data-segments.mjs "$CLI"` 构造并由 V8 独立验证一个38字节
混合模块，一张 memory、三个条目。固定编码：

```text
0061736d0100000005030100010c01030b140300410b0b036162630100020041000b0378797a
```

SHA-256：`1cd4ff01e7869a1fd4cf8f03261e7af6484226e9b5bc06318e0cdd3405f6d46a`。
首次本地 CLI 运行记录位于 `_build/data-segments-verification/run-KOKUko/`，
包含输入、完整 JSON、日志和精确退出状态。每次脚本新建目录，不覆盖旧证据。
下列数字来自实际 CLI 结果：

| 原始序号 | 模式 | memory | 条目 file offset | 完整编码 B | payload file offset | payload B |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| 0 | active | 0 | 19 | 8 | 24 | 3 |
| 1 | passive | 不适用 | 27 | 2 | 29 | 0 |
| 2 | active | 0 | 29 | 9 | 35 | 3 |

data 段从 file offset 16 开始，完整22 B：段头2 + 数量字段1 + 条目8、2、9。
payload 总6 B，条目元数据13 B，段级开销3 B；6 + 13 + 3 = 22。
datacount 独立占3 B，声明3条，不计入22 B。条目0的表达式从 file offset 20
开始，占3 B（`i32.const 11; end`），立即数为 `0x0b`，仍正确包含结束指令。
文本 Top 1 显示原始序号0；完整 JSON 仍保留三个条目。

## 库入口与 JSON

```moonbit
inspect_data_segments(data : Bytes) -> Result[DataSegmentsReport, WasmError]
render_data_segments(report : DataSegmentsReport, top : Int) -> String
render_data_segments_json(report : DataSegmentsReport) -> String
```

入口内部调用 `parse_module`，只保存元数据，不复制全部 payload。没有给 Analysis、
WasmModule、Sections 增加必填字段，没有修改 analyze 签名。

JSON 独立使用 `format: "moonsize-data-segments"`、`schema_version: 1`：
`summary` 包含段存在性、file offset、完整大小、段头、数量字段、条目数、payload、
条目元数据和段级开销；`datacount` 是声明数量或 null；`entries` 为原序数组。
每条包含 `encoding`、`payload`、`offset_expression` 范围及各字段的实际宽度。
不输出原始内容、求值偏移或删除收益，不修改调用图或 HTML schema。

迁移注意：WasmError 新增 `InvalidDataEncoding(Int, String)`，携带文件位置和
模式/数量错误原因，外部穷举匹配须补充分支。Reader/指令错误和尾随字节继续使用
原错误类别；Options 增加 `data_segments`、`data_json`，默认分别为 false、None。

本地只做新增及受影响测试、native 检查和一次 release 构建；完整回归由目标提交
Linux CI 执行。HTML、跨构建条目匹配、重复内容分析和新预算指标留到后续。
