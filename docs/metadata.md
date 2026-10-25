# 自定义段与符号名称开销

这是公开0.5.1之后的源码增量，需使用当前源码构建的native CLI；本次不改版本、
不发布Mooncakes。报告只解释文件编码字节，不删除或修改输入。

```sh
moonsize app.wasm --metadata --top 20
moonsize app.wasm --metadata-json new-metadata.json
```

独立模式只允许Top和自身JSON；JSON隐含启用，要求新的`.json`路径，并沿用统一
预检与独占创建。strict及其他分析模式在参数阶段被拒绝，不读取输入。Top限制
自定义段、子段和函数名记录的文本详情，完整汇总、覆盖状态、诊断和JSON不截断。
0表示已完成报告（可能只有部分名称明细），1表示读取、外层结构或写入错误，
2表示参数错误。没有新增压缩、图完整性、HTML或删除收益指标。

## 范围和分类

所有custom实例分别保存物理序号、在全部段中的序号、完整范围及分解。相同名称
的多个实例不会覆盖彼此。文件范围以`offset`和`size`表示半开区间，均是file
offset，不是内存地址。

分类只使用从原始有界范围严格解码得到的完整UTF-8名称，不使用旧解析器的有损
显示标签。精确的`name`与`producers`分别分类，`.debug_`前缀归入debug，其他可靠
名称归入other。debug是名称分类，不证明内容是合法DWARF；producers和debug内容
保持opaque，不解释内部格式。空名称合法，按other计入。

名称UTF-8无法读取时，保留原范围、大小和诊断，名称为null，归入unavailable。
所有不可用名称仅合并到一个**核算桶**，不声称它们字节相同，也不与含有合法
U+FFFD字符的名称混为一组。没有收紧既有parse_module的UTF-8接受行为。

## name明细与失败边界

遍历所有可可靠识别的name实例，而不是只处理分析器选中的有效名称段。每个
可定界子段保留物理序号、id、完整范围、头部和payload范围。只有id1按函数名映射
深入解析，其他id作为opaque正常保留；`complete`仅表示本入口支持的解释完成。
旧函数名称选择、显示名称和符号解析行为不变。

函数名记录保留custom/子段/记录序号、声明索引、完整范围、索引前缀、名称长度
前缀及UTF-8字节范围。同名、同索引和多个name段里的物理记录全部保留，不校验
声明索引是否真的存在。索引和声明数量使用完整u32，JSON不会把高位值显示成负数。
实际编码长度包括合法非最短LEB编码。

可选内容损坏不会自动成为外层模块错误。这与[Wasm自定义段的处理规则](https://webassembly.github.io/spec/core/binary/modules.html#custom-section)
一致；本入口没有放宽原有外层结构检查。

- 记录无法读完：保留此前记录，从失败记录起点核算余量，包括已消费的索引和
  长度字段；继续下一个已定界子段。
- 记录可定界但名称UTF-8损坏：保留该记录，name为null，继续后续记录。
- 数量前缀失败：count为null，count_prefix_bytes为0，整个payload计入未解析。
- 声明记录结束后有尾随字节：计入未解析范围并报告诊断。
- 子段头或payload无法定界：从该子段头起记录unbounded_tail，停止本name段；
  后续custom实例仍继续读取。
- 模块、custom名称长度或段范围无法安全读取：沿用WasmError，CLI返回1。

`byte_ledger_complete`、`custom_name_status`和`name_details_status`分别描述字节
核算、custom名称解码和支持范围内的name解释。无可靠name段时明细为absent；
可选内容坏时为partial，并附文件位置、父序号和原因。opaque不是失败；退出0
不证明全部可选内容都已理解，更不证明完整Wasm语义合法。

## 实测账本

`scripts/test-metadata.mjs`确定性生成123字节混合custom样本，SHA-256：
`6ee9a5d2f131de3b8381855ae29836b0570c26f2f5832dc5e1e7cfc7724a1967`。
它经Node/V8独立验证一次，包含两个name、一个debug、一个producers、两个同名
中文custom及一个空名称custom；无函数定义，故函数名声明不构成函数存在证明。

实际CLI结果：

```text
Custom sections: 7; 115 B (93.4% of file)
Custom bytes: 115 B = section headers 15 B + custom-name encodings 48 B + contents 52 B
Name contents: 45 B = bounded subsections 45 B + unbounded tails 0 B
Function-name payloads: 36 B = count prefixes 3 B + parsed records 33 B + unparsed 0 B
Parsed record bytes: 33 B = index prefixes 8 B + name-length prefixes 5 B + name UTF-8 20 B
```

类别完整字节分别是name 61、producers 14、debug 17、other 23；合计115。
两个`说明`实例分别10和9字节，同名汇总19字节；实例不丢失。第一个name段实际
使用两字节段长度、custom名称长度、子段长度和记录数量前缀。

函数名记录按完整编码大小降序、文件偏移升序排列，实际结果：

| custom / sub / record | 声明索引 | 名称 | 文件偏移 | 完整编码B |
| --- | ---: | --- | ---: | ---: |
| 3 / 0 / 0 | 2 | longer-name | 83 | 13 |
| 0 / 0 / 2 | 4294967295 | 雪 | 32 | 10 |
| 0 / 0 / 0 | 1 | dup | 22 | 5 |
| 0 / 0 / 1 | 1 | dup | 27 | 5 |

其中最大索引使用五字节u32，`雪`的名称长度使用两字节合法非最短编码。Top1
仅展示第一条详情，JSON仍包含四条记录、三个子段和全部七个custom。

57字节部分内容损坏样本SHA-256：
`2f41093da62d526884a6c88ca0919209f8a31d123c24fcfd3208ef7a90f6dab0`。
CLI返回0，字节账本complete、name明细partial，两条诊断；失败记录余量3字节，
无法定界尾部2字节，后续`later`和另一name段的`after`均被保留：

```text
Custom bytes: 49 B = section headers 4 B + custom-name encodings 10 B + contents 35 B
Name contents: 35 B = bounded subsections 33 B + unbounded tails 2 B
Function-name payloads: 24 B = count prefixes 3 B + parsed records 18 B + unparsed 3 B
```

每层是父范围的分解，不能将父项与子项再相加。custom完整大小包含section id、
长度前缀和payload；custom-name编码包含名称长度前缀和名称字节；内容是其后
剩余范围。名称字节总量包含已定界但UTF-8不可用的记录，不把它们记成零。

## API、JSON与验证

```moonbit
inspect_metadata(Bytes) -> Result[MetadataReport, WasmError]
render_metadata(MetadataReport, Int) -> String
render_metadata_json(MetadataReport) -> String
```

JSON独立使用`format: moonsize-metadata`、`schema_version: 1`。包含输入大小、实际
SHA-256、custom占整文件比例、全部汇总、名称组、实例、子段、记录、未解析范围、
覆盖状态及诊断；不输出原始payload。新增九种Metadata类型及Options的metadata、
metadata_json字段，旧签名、WasmError、Sections与旧报告格式不变，见[迁移说明](migration-0.5.md)。

本地只执行metadata_wbtest.mbt里的3个新组合测试及脚本的4次真实CLI调用：文本
Top1、完整JSON、外层合法但name内容损坏、已有JSON拒绝（返回1且原字节不变）。
单测另涵盖UTF-8不可用、未知子段、失败数量、尾随字节、空模块、外层错误和参数
冲突；未执行旧套件、编译探针、浏览器/PDF、演示或性能基准。

```sh
moon test --target native metadata_wbtest.mbt
node scripts/test-metadata.mjs _build/native/release/build/cmd/main/main.exe
```

本地证据为`_build/metadata-verification/run-SWLCRC/`（两份输入、四次日志、完整
JSON及results.json）；这是本机位置，不是公开下载地址。CI复用native构建追加
同一脚本，既有回归由现有CI自动执行，目标SHA状态在提交推送后单独核对。

metadata可能被调试器、加载器或其他工具使用；本入口不证明可以安全删除，
不解释运行时内存、源码归属、重编译减量或gzip/传输收益。

## 自定义段编码开销基线比较（公开0.5.1后的源码增量）

```sh
moonsize after.wasm --baseline before.wasm --diff-metadata --top 20
moonsize after.wasm --baseline before.wasm --diff-metadata --metadata-json new-metadata-diff.json
```

compare_metadata每侧各调用一次inspect_metadata，保留原报告和既有SHA-256，不再
解析或哈希。外层错误沿用ComparisonError的Baseline/Current，整体失败；没有
custom、合法空名称、opaque和内部name明细partial均可成功。

比较只核算custom外层完整编码：段头（含实际长度前缀）、名称编码、内容。按
name、producers、debug、other、unavailable固定顺序汇总，再按完整UTF-8名称
精确分组，不trim、不忽略大小写、不归一化。重复名称的全部实例和双侧ordinal
列表保留，不按ordinal建立跨构建配对。ordinal仅定位各自输入里的物理实例。

不可用名称的组为kind=unavailable_names、name=null，只用于核算；合法空名称、
字面名称(unavailable)和合法U+FFFD不会混入该桶。分类与名称是同一集合的两种
视图，不能相加。debug只依据名称前缀，不验证DWARF。名称相同、数量相同或字节
差为零都不证明内容相等；不比较name子段、函数名记录增删或部分解析的内部差异。

双侧byte_ledger_complete、custom_name_status、name_details_status、diagnostics、
未解析范围和所有原始明细完整保留。文本在表前列覆盖、诊断和未解析范围；外层
账本完整可以同时伴随name_details_status=partial。opaque表示未解释，不是失败。

### 实测外层账本

scripts/test-metadata-diff.mjs在Node v24.18.0下生成三份外层合法样本，分别V8验证
一次，不实例化、不执行。基线60 B，SHA-256：
8d3c563a287db4683342358fef8841b68520d2d27f88295dbce37da27685b645。
当前62 B，SHA-256：
5866b9fd5dd876b48be77cb6734a62d2f6109fd2a0f83d46144ced5da172f760。

实际CLI输出：

```text
Baseline custom: 52 B = headers 12 B + name encodings 32 B + contents 8 B; 6 instances
Current custom: 49 B = headers 11 B + name encodings 27 B + contents 11 B; 5 instances
Custom delta: -3 B = headers -1 B + name encodings -5 B + contents 3 B; count delta -1
Non-custom: 8 -> 13 B
File delta: 2 B = custom -3 B + non-custom 5 B
```

分类编码差依次为name 0、producers -13、debug -1、other +11、unavailable 0，
合计-3。完整名称组有6组，Top1只展示producers；JSON仍有两侧全部6/5个实例。
x在基线出现两次、当前一次，双侧ordinal为[1,2]和[1]；两边完整编码均10 B，
但次数和内容不同。当前x使用两字节段长度及名称长度前缀，按实际输入宽度核算。

所有差值为current-baseline，不是文件范围。每组完整编码差等于段头、名称及
内容差之和；分类/名称各自的数量、双侧字节和差值分别闭合。non_custom_bytes
包含Wasm头、code和全部标准段，不是“非code”或“其他元数据”。

JSON摘要节选（实际值；完整文件还保留两侧报告、全部组和成员ordinal）：

```json
{
  "format": "moonsize-metadata-diff",
  "schema_version": 1,
  "delta": {
    "custom_count": -1,
    "custom_encoded_bytes": -3,
    "section_header_bytes": -1,
    "name_encoding_bytes": -5,
    "content_bytes": 3
  },
  "delta_file_bytes": 2,
  "delta_non_custom_bytes": 5
}
```

完整JSON的baseline/current是原moonsize-metadata报告对象，不是序列化字符串。
单文件JSON及原render_metadata_json接口不变。名称组按完整编码差绝对值、数量
差绝对值降序，再按完整名称字典序，等优先级的不可用桶最后；Top只限制文本
名称组，不截断分类、汇总、覆盖、诊断或JSON。

### 用法与验证范围

--diff-metadata隐含metadata，baseline必须非空；显式重复--metadata不增加解析。
没有diff标志的metadata加baseline仍返回2。比较模式只允许baseline、Top、自身
JSON和metadata标志；strict、max-size、预算、HTML、compress及其他模式在读取
输入前拒绝。退出0表示比较完成（包括增长、无custom、partial），1为读取、
外层结构或输出失败，2为参数错误。JSON仍要求新的.json目标，复用统一预检及
原生独占创建。没有新增覆盖或事务保证。

新增API为compare_metadata、render_metadata_diff、render_metadata_diff_json，
新增MetadataEncodingTotals、MetadataComparisonGroup、MetadataComparison及
Options.diff_metadata；见[迁移说明](migration-0.5.md)。

本地仅3个新组合单测及4次CLI，状态0/0/0/1：混合样本文本Top1、完整JSON、
内部name损坏但外层合法的partial JSON、已有JSON拒绝且原字节不变。无效UTF-8
样本只验证旧解析器兼容行为，不宣称V8合法。本地证据：
_build/metadata-diff-verification/run-MYjdpn/，含三份输入、四份日志、
metadata-diff.json、partial-diff.json及results.json。可重现命令：

```sh
moon test --target native metadata_diff_wbtest.mbt
node scripts/test-metadata-diff.mjs _build/native/release/build/cmd/main/main.exe
```

本地未运行旧套件、演示、浏览器/PDF或性能基准；CI沿用既有回归，只追加一次
轻量脚本，目标SHA的整体状态在推送后独立核对。版本与依赖不变，未发布Mooncakes。
本功能不比较内容、不推断稳定身份、语义或安全strip，不预测重编译与gzip收益。
