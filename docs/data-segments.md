# Wasm 数据段编码明细

本功能纳入 0.5.0 源码；实际发布与精确版本消费状态见
[0.5.0 发布记录](https://github.com/BigSaltyMan/moonsize/releases/tag/v0.5.0)，
接口变化见[迁移说明](migration-0.5.md)。它解释 data 段中哪些文件字节属于初始化 payload，哪些属于编码元数据。
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

## 同一产物的数据段重复内容（0.5.1之后的源码增量）

```sh
moonsize app.wasm --data-duplicates --top 20
moonsize app.wasm --data-duplicates-json new-data-duplicates.json
```

这是独立模式，JSON选项隐含启用；只允许Top和自身JSON。普通data-segments、
data-json、diff-data、baseline、函数duplicates、strict、预算、HTML及其他分析
模式在参数阶段返回2，读取前拒绝。成功（含无data/无重复）返回0，读取、结构、
保护和写入失败返回1。新JSON目标沿用统一preflight及原生独占创建；解析失败
不创建报告，不新增writer、覆盖开关或事务保证。

### 比较范围和成员证据

只比较DataSegment.payload原始字节，不含模式、memory索引、offset表达式或
payload长度前缀。与--duplicates的函数body比较及--diff-data的双侧内容组比较
分别独立，不扩展原有组合。相同payload在不同active/passive、memory、表达式
及前缀下仍归组，但这些元数据不会丢失，也不因此推断初始化语义相同。

每次只inspect_data_segments一次，保留原始DataSegmentsReport与整文件大小、
SHA-256。每条payload计算一次摘要，完整摘要/长度筛选桶，再用现有
data_payload_equal复核实际字节，不做全部条目两两比较。通过有界Reader取得
临时view；SHA接口需要的一次临时Bytes复制不进入报告，桶view也不长期保留。
摘要碰撞且字节不同会分别成桶，不把摘要当唯一身份。

成员为当前文件的原始DataSegment.index，升序保存；组id取最小成员索引，只在
本报告内有效，不承诺跨构建稳定。组按全部成员payload字节降序、单份payload
大小降序、最小索引升序排列。至少两个成员才列组，单例参与完整统计；多个空
payload构成零字节组，仍有编码元数据，不因payload大小为零而过滤。

Top只限制文本组数，每组固定最多预览20成员，并显示已展示数/总数；JSON保留
全部组、全部成员index及原始条目。预览和排序不改变组id。无data、空data和空
payload分别保留原状态。文件offset是文件位置，不是内存地址；active表达式为
not_evaluated，passive为not_applicable，不新增内存偏移求值。

### 实测组和闭合账本

scripts/test-data-duplicates.mjs生成74字节合法样本，SHA-256：
d12f4870b8e467bfee1200e59d15c252fae90e39267f5b372df684d5ca309721。
Node v24.18.0/V8仅验证这个混合fixture一次，不实例化或执行。样本有两张memory、
DataCount8及三种data编码，包含非最短的段长度、数量、模式、memory索引和
payload长度编码。原条目证据：

| index | mode | memory | encoding file offset | encoded B | payload file offset | payload B |
| ---: | --- | ---: | ---: | ---: | ---: | ---: |
| 0 | active | 0 | 23 | 8 | 28 | 3 |
| 1 | passive | 不适用 | 31 | 7 | 35 | 3 |
| 2 | active | 1 | 38 | 10 | 45 | 3 |
| 3 | passive | 不适用 | 48 | 4 | 50 | 2 |
| 4 | active | 0 | 52 | 9 | 59 | 2 |
| 5 | passive | 不适用 | 61 | 5 | 63 | 3 |
| 6 | passive | 不适用 | 66 | 2 | 68 | 0 |
| 7 | active | 0 | 68 | 6 | 74 | 0 |

完整JSON实际包含三组（表中payload仅用于解释夹具，不作为报告内容预览）：

| id | payload | 单份B | 全部成员index | 成员payload B | 成员元数据B | 成员编码B |
| ---: | --- | ---: | --- | ---: | ---: | ---: |
| 0 | abc | 3 | 0, 1, 2 | 9 | 16 | 25 |
| 3 | xy | 2 | 3, 4 | 4 | 9 | 13 |
| 6 | 空 | 0 | 6, 7 | 0 | 8 | 8 |

index5的xyz与abc等长但内容不同，是单例。组0含隐式memory0、passive和显式
memory1；表达式分别从file offset24和41起占3字节，包含结束指令，立即数11
中的0x0b不会被误作表达式结尾。元数据宽度和表达式范围全部在原始明细里保留。

```text
Duplicate groups: 3; segments: 8 = duplicate-group members 7 + singletons 1
Payload bytes: 16 B = duplicate-group members 13 B + singletons 3 B
Entry encoding bytes: 51 B = payload 16 B + metadata 35 B
Duplicate-member encoding bytes: 46 B = payload 13 B + metadata 33 B
Singleton encoding bytes: 5 B = payload 3 B + metadata 2 B
Data section bytes: 56 B = section header 3 B + count prefix 2 B + entries 51 B
```

DataCount独立3字节，不计入56字节data段。每组核对成员payload字节=单份大小×
成员数，以及成员编码=payload+元数据；生产代码用受检查的累计，转换回Int前
核对范围，避免乘法溢出。duplicate_member_payload_bytes为所有重复组成员的
payload总和13，不是去掉一份后的余量，更不是可节省量。相同内容可能有不同
目标、时机和初始化操作，未证明用途等价，不推断安全合并、重编译或整文件gzip
减量，也不分析字符串、子串、相似内容或运行时用途。

### 新接口、JSON和定向验证

```moonbit
inspect_duplicate_data(Bytes) -> Result[DuplicateDataReport, WasmError]
render_duplicate_data(DuplicateDataReport, Int) -> String
render_duplicate_data_json(DuplicateDataReport) -> String
```

新增DuplicateDataGroup、DuplicateDataSummary、DuplicateDataReport，以及Options的
data_duplicates=false、data_duplicates_json=None。旧inspect_data_segments、
compare_data_segments、WasmError和既有JSON不变，不调用analyze、图或自比较。
新JSON独立使用moonsize-data-duplicates/schema_version1：完整data_segments复用旧
明细结构；groups通过member_indices回查所有条目、模式、memory、encoding、
payload、offset_expression及前缀大小；summary含全部成员/单例统计和分层账本。
无原始payload内容、优化收益或未经计算的graph_complete字段。

本地仅3个data_duplicates_wbtest.mbt组合测试，含21个空成员的20/21预览和排序
并列、私有插桶helper强制相同摘要的碰撞复核，以及一个DataCount错误透传。
没有公开测试开关，不重跑旧parser/data-diff/函数duplicates。真实CLI仅四次：
混合文本Top1、同产物完整JSON、合法无data模块、已有JSON拒绝且字节不变。

```sh
moon test --target native data_duplicates_wbtest.mbt
node scripts/test-data-duplicates.mjs _build/native/release/build/cmd/main/main.exe
```

实际证据_build/data-duplicates-verification/run-cMyCZN/含两份输入、四次日志、
完整JSON及results.json。完成必要接口/格式/native检查和一次release构建；未在
本地运行旧套件、旧CLI、演示、探针、浏览器/PDF或性能基准。CI复用native构建
仅追加同一轻量脚本，旧回归自动执行；提交后核对最终SHA整体结果。版本保持
0.5.1，不改依赖、不发布Mooncakes。

## UTF-8 payload内容检索（0.5.1后源码增量）

`--find-data "assets/logo"`在每个payload内按UTF-8字节精确匹配，
`--find-data-json new-search.json`保存完整命中及原始数据段账本。
它是独立查询，不与明细、比较、HTML或strict组合；使用Top限制文本命中行。
空格不trim、重叠命中保留、不跨段、不搜索表达式或其他编码。文件偏移不是
内存地址，查询文字也会写入报告。命中不证明独立字符串、资源用途、可安全
去重或删除收益；无命中不证明内容不存在。旧重复payload功能仍只比较完整
payload，此新入口独立搜索子串，不改变旧格式或语义。
[完整规则、公开接口和真实43 B样本](data-search.md)。
