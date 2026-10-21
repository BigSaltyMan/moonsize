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
"$CLI" app.wasm --html new-report.html --data-segments
"$CLI" app.wasm --html new-report.html --data-json new-data.json
```

`--data-json` 隐含启用文本明细，要求新的 `.json` 文件。未启用这两个选项时，
默认报告不变。文本复用 `--top`（默认10），按 payload 长度降序、原始序号升序
排列；Top 只限制显示，汇总包含全部条目，JSON 按原始序号保留全部条目。

可组合普通文本、`--retained`、`--dead-code`、`--compress`、`--strict`、
`--max-size` 和 `--baseline`。未启用 `--diff-data` 时，baseline 仍只执行原有
比较，不比较数据条目。
暂不与调用图导出、experiment、函数路径、budget 或 `--diff-functions`
组合；参数阶段拒绝这些组合并返回2，在读取输入前报错。

解析错误、输出保护或写入失败返回1。解析在正常输出前完成；strict 仍在目标
预检查和写入前拒绝不完整图并返回3。原有 max-size 行为不变，超限仍可保存明细
后返回3。新 JSON 使用统一预检查及原生独占创建，不删除已有目标。这不提供
多文件事务；后续失败可能留下之前的新文件或本次新建的部分文件。

## HTML 当前输入明细

HTML 必须显式配合 `--data-segments` 或 `--data-json`，不改变默认 HTML 的数据解析
成本。HTML 和单文件 JSON 复用同一份报告，先检查全部目标，再独占创建；不是
多文件事务。HTML 模式不在终端重复输出数据表。即使传入 baseline，页面模块也
只表示 current input，`--html --diff-data` 仍在读取输入前以2拒绝。

摘要、闭合账本和按 payload 排序的前20条直接写入 HTML，无 JavaScript 或图表库
仍可读。完整元数据内嵌在可选 `DATA.dataSegments`，不含原始 payload。更多条目
从元数据每批追加20条；持续显示已展示数/总数，全部展示后按钮隐藏。`--top` 仍
只影响文本，不是 HTML 分页参数。表格可在窄屏内部横向滚动；文件范围通过原生
details/summary 展开，支持键盘，不依赖 hover。三种空态与单文件账本一致。

打印保留摘要、已展示行和数量，明确这是子集；打印前不追加全部条目。只展开已
展示行的初始化描述，结束后恢复原状态。文件偏移不是内存地址，文件字节不是
运行时内存占用，表达式未求值，也没有源码归属或删除收益推断。

新增库入口 `render_html_with_data_segments(analysis, file_path, report, echarts?)`，
report 须来自同一 `analysis.data` 的 inspector。原 `render_html` 签名不变；共用
模板和一次压缩测量，渲染时不再解析数据段。CLI 继续内嵌固定 ECharts，不新增
外部请求。实测浏览器、打印和正式示例记录见[HTML 交付验收](html-delivery.md)。

## 按 payload 内容分组的基线比较

```sh
"$CLI" after.wasm --baseline before.wasm --diff-data
"$CLI" after.wasm --baseline before.wasm --diff-data --top 20
"$CLI" after.wasm --baseline before.wasm --diff-data --data-json new-diff.json
```

`--diff-data` 必须提供 baseline，隐含启用当前数据明细，并追加两侧内容组比较。
除仍拒绝 HTML 外，组合限制、strict、max-size 退出码和输出保护沿用单文件模式；坏 baseline/current
均在正常输出和创建目标前失败。主程序只读取 baseline 一次，直接复用比较结果的
当前明细，不重复调用当前数据 inspector。原有模块段表检查和分析流程仍保留。

完整文件 SHA-256 识别两侧产物；payload SHA-256 只用于分桶，命中后仍核对长度
和实际字节。重复项、空 payload 按出现次数累计。重排不制造内容新增/消失；
payload 改变时给出两侧独有内容组，不猜测哪两个条目是“同一条目修改”。

内容组分类为 `shared_payload`、`baseline_only`、`current_only`。保存两侧索引、
次数、payload/完整条目/元数据总量及 current − baseline 差值，差值可正、负或零。
两侧完整明细保留 mode、memory 和未求值的表达式范围。即使内容、次数和大小都
相等，也不标记“完全未变化”，因为本功能不比较初始化语义。

```text
delta(data section) = delta(payload) + delta(entry metadata) + delta(header + count)
sum(group encoded delta) = delta(payload) + delta(entry metadata)
```

datacount 仍单独保留，不加入 data 账本。相同 payload 因模式、表达式或非最短
编码不同，也可能有元数据差值。内容组不是源码身份；相同内容不证明初始化语义
等价，重复内容不证明可安全去重；原始字节差值不预测重编译或整文件 gzip 收益。

文本按完整条目差值绝对值降序，然后完整摘要字典序、单份长度和报告内 group id
升序。id 来自先 baseline 文件顺序、再 current 尚未出现内容的发现顺序，亦可
区分同一完整摘要下不同实际字节的组。摘要前12位只用于显示，不是唯一身份。
Top 仅限制文本行数，汇总和 JSON 全量保留；JSON 的组数组按发现顺序排列。

比较 JSON 独立使用 `format: "moonsize-data-segments-diff"`、`schema_version: 1`。
`baseline` / `current` 包含作为标签的 path、实际文件 sha256 及原格式的完整 details；
`groups` 含完整摘要、索引和两侧总量/差值，`delta` 含段级差值。仅在 `--diff-data`
开启时，`--data-json` 才写这种格式；单文件的 format、schema 和渲染签名不变。

### 本次比较实测（2026-10-21）

扩展后的轻量 CLI 脚本使用下述实际输入，两个合法模块均由 V8 独立验证：

- baseline：下文38字节混合样本，data 22 B，payload 6 B，条目元数据13 B。
- current：31字节，三个 passive 条目，payload 依次为 `abc`、`abc`、空；
  data 15 B，payload 6 B，条目元数据6 B，段级开销仍为3 B。

current 编码为
`0061736d0100000005030100010c01030b0d03010361626301036162630100`，SHA-256 为
`9b1f873793772c31c68ae8567aa7b01033b09f52ab9142d1b387935f81b54fdc`。

| 内容（仅此已知 fixture 的说明标签） | 分类 | 前/后次数 | payload 差值 B | 完整条目差值 B | 元数据差值 B |
| --- | --- | --- | ---: | ---: | ---: |
| abc | shared_payload | 1 / 2 | +3 | +2 | -1 |
| 空 | shared_payload | 1 / 1 | 0 | 0 | 0 |
| xyz | baseline_only | 1 / 0 | -3 | -9 | -6 |

账本：data 差值 -7 = payload 0 + 元数据 -7 + 段级开销0；组完整条目差值
+2 + 0 - 9 = -7。datacount 两侧各3 B，均声明3，不计入 data 差值。
这里的 abc/xyz 是合成输入的已知说明，产品不解析或输出字符串内容。
Top 1 展示 xyz 内容组，完整 JSON 仍包含三个组和两侧全部明细。

首次实际证据：`_build/data-segments-verification/run-KnKfj2/` 的 `diff.json`、
`cli-5.log` 及 `verification.json`。每次脚本新建运行目录；没有为本功能重跑
性能基准、HTML/PDF 或源码演示。

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

比较入口为 `compare_data_segments(baseline, current)`，返回
`Result[DataSegmentsComparison, ComparisonError]`，错误分别为 Baseline/Current；
结果保留两侧明细、完整文件摘要、内容组和差值。
`render_data_segments_diff(report, baseline_path, current_path, top)` 生成文本，
`render_data_segments_diff_json(report, baseline_path, current_path)` 生成完整 JSON。
路径只作标签；结果不保留原始 payload 内容。Options 仅再增加默认 false 的
`diff_data`；旧 DataSegmentsReport 和公开函数签名没有变化，没有新增依赖。

本地只做新增及受影响测试、native 检查和一次 release 构建；完整回归由目标提交
Linux CI 执行。HTML 仅展示当前明细；跨构建稳定条目匹配、字符串/模糊分析、自动去重建议、
offset 求值和新预算指标留到后续。
