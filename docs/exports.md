# 导出接口清单与声明别名

这是公开0.5.1之后的源码增量，需从当前源码构建native CLI；版本未变，未发布
Mooncakes。入口只读输入，不修改Wasm，也不执行其中代码。

```sh
moonsize app.wasm --exports --top 20
moonsize app.wasm --exports-json new-exports.json
```

## 范围、名称和目标

支持function、table、memory、global、tag五类导出。inspect_exports先复用
parse_module的基础结构检查，再独立深入export段并计算一次SHA-256；不构图、
不读取函数清单、不解码指令，也不调用imports或entrypoints检查入口。

名称严格按UTF-8解码，保留空字符串、空白、大小写、点号、Unicode和控制字符；
不trim、不归一化、不demangle。它是宿主可见的导出名，不是内部符号或源码名。
文本用JSON字符串写法转义控制字符，JSON字符串则保留原值。

所有kind之间的重复导出名都拒绝，错误指出重复声明和首次声明的file offset。
这符合[导出名唯一性要求](https://webassembly.github.io/spec/core/valid/modules.html#valid-module)，
但不代表本工具完成了模块语义验证。未知kind、非法UTF-8返回
InvalidExportEncoding(offset, reason)，已有有界读取、LEB和尾随错误继续复用；
不输出partial。声明数量读完后，payload必须恰好耗尽。

ordinal是文件内声明物理序号；target_index是对应kind索引空间里的完整u32，
JSON用数字保存，不经有符号Int转换。function #0、table #0、memory #0分开。
不验证目标是否存在、签名、类型、导入或本地来源。函数导出可以重导出宿主
导入，没有本地body；本报告不会伪造零字节函数或估计宿主成本。

按(kind,target_index)生成全部声明目标组。至少两条不同名称的声明为别名组；
单成员目标仍留在JSON中。别名是声明关系，不证明目标有效、语义等价、可达性
或可安全删除。需要根与可达编码量时，使用独立的--entrypoints；函数索引可供
后续--instructions/--callers查询，但索引有效性和本地body要求由相应入口检查。

## 编码范围与闭合账本

每条声明保留encoding、name_encoding、descriptor的offset/size半开文件范围。
name_encoding含长度前缀和名称UTF-8；descriptor含kind与目标索引前缀，kind每条
恰好一字节。长度及索引都核算实际编码宽度，包括合法非最短编码。

```text
export_section_bytes = section_header_bytes + count_prefix_bytes + declaration_bytes
declaration_bytes = name_encoding_bytes + descriptor_bytes
name_encoding_bytes = name_length_prefix_bytes + name_utf8_bytes
descriptor_bytes = kind_bytes + target_index_prefix_bytes
```

所有目标组的声明字节合计为declaration_bytes，不把段头或count分摊给目标。

```text
export_count = alias_member_count + singleton_target_count
distinct_target_count = alias_group_count + singleton_target_count
sum(kind_counts) = export_count
```

无export段时section/count_encoding为null、账本为零；显式零条目段仍保留段头和
count字节。范围是file offset，不是内存地址。这些字节不包含函数body、依赖闭包、
memory容量或宿主实现；即使别名各有声明开销，也不能推算安全删除或gzip收益。

## 实测样本

scripts/test-exports.mjs确定性生成126 B混合样本，Node v24.18.0/V8独立验证一次，
未实例化或执行。SHA-256：

```text
4809ecf99fa7caabdb0b31fccb5cb97231c8dc3eb522847e7a71922485eea8d3
```

夹具的五类资源都来自导入；这由夹具构造可知，清单本身不推断来源。实际结果：

```text
Kinds: function 3; table 2; memory 1; global 1; tag 1
Declarations: 8; distinct declared targets: 5
Alias groups: 2; alias members: 5; singleton targets: 3
Export section: 57 B = headers 3 B + count 2 B + declarations 52 B
Declarations: 52 B = name encodings 35 B + descriptors 17 B
Name encodings: 35 B = length prefixes 9 B + UTF-8 26 B
Descriptors: 17 B = kind 8 B + index prefixes 9 B
```

| kind / target | 成员ordinal | 声明数 | 声明编码B | 是否别名 |
| --- | --- | ---: | ---: | --- |
| function / 0 | 0, 1, 7 | 3 | 24 | 是 |
| table / 0 | 2, 3 | 2 | 12 | 是 |
| memory / 0 | 4 | 1 | 6 | 否 |
| global / 0 | 5 | 1 | 4 | 否 |
| tag / 0 | 6 | 1 | 6 | 否 |

export段在file offset69，长度57；段头3 B，count在72、宽2 B。第一条从74开始，
名称和目标索引均使用两字节前缀。Top1声明是ordinal1的`"f alias"`，10 B，
file offset80。别名表Top1展示function #0的三个名称：`"f"`、`"f alias"`、
`"雪\"\n"`，控制字符按转义写法显示。完整JSON保留8条物理声明和5个目标组。

重复名称样本将第三条table声明名改为f，CLI返回1：

```text
invalid export encoding at offset 90: duplicate export name "f"; first declaration at file offset 74
```

指定的新JSON没有创建。另一场景对已有JSON返回1且原字节不变。

## CLI、JSON和迁移

--exports-json隐含启用独立清单，只允许Top与自身JSON；目标必须是新的.json路径。
baseline、strict、其他查询/比较、HTML、compress、预算等在读取输入前返回2。
成功（包括无导出）返回0；读取、解析、保护或输出失败返回1。不复用图strict
语义，也不增加graph_complete字段。沿用统一预检和原生独占创建，无新writer。

Top分别限制声明表和别名表，不截断汇总、全部条目或JSON。声明按编码大小降序、
ordinal升序；别名按成员数降序、kind编码/完整UInt索引升序。每组文本最多预览
20个名称并显示已展示/总数，完整成员始终在JSON里。Top不是分析资源限制。

```moonbit
inspect_exports(Bytes) -> Result[ExportsReport, WasmError]
render_exports(ExportsReport, Int) -> String
render_exports_json(ExportsReport) -> String
```

JSON独立使用format=moonsize-exports、schema_version=1，包含file_size、实际
sha256、section/count_encoding、summary、ledger、entries、targets、supported_scope。
嵌套数据是对象，非字符串。entries按物理顺序，targets按kind编码和UInt索引，
entry_ordinals升序，包含单成员目标。没有原始函数body、签名或删除收益。

新增7种只读结构和Options.exports/exports_json；外部穷举匹配WasmError需处理
InvalidExportEncoding。旧Export、parse_export_section、entrypoints及旧报告格式
不变；见[API迁移说明](migration-0.5.md)。

本地仅3个新组合单测与4次真实CLI，精确状态0/0/1/1：文本Top1、完整JSON、
重复名拒绝且无报告、已有JSON保护。单测覆盖空态、完整u32、跨kind隔离、实际
前缀宽度、转义和错误；越界目标及未知opcode样本仅验证本入口不做相应语义
检查，不宣称它们是V8合法模块。

```sh
moon test --target native exports_wbtest.mbt
node scripts/test-exports.mjs _build/native/release/build/cmd/main/main.exe
```

本地证据在_build/exports-verification/run-8yg23B/，含输入、四份进程日志、完整
exports.json及results.json。本地未跑旧套件、旧CLI、探针、演示、浏览器/PDF或
性能基准。CI保留旧回归，只追加轻量exports脚本；最终SHA整体结果推送后独立
核对。版本保持0.5.1，依赖不变，本次未发布Mooncakes。

## 导出接口清单基线比较

这是公开0.5.1后的源码增量，版本与依赖不变，未发布新包。

```sh
moonsize after.wasm --baseline before.wasm --diff-exports --top 20
moonsize after.wasm --baseline before.wasm --diff-exports --exports-json new-exports-diff.json
```

compare_exports每侧只调用一次inspect_exports，复用严格清单、完整报告和既有
SHA-256，不重新解析/哈希，不建图、不匹配函数或读取签名。重复名、UTF-8、kind
及范围错误均沿用单侧入口，整体失败；ComparisonError保留Baseline/Current，
CLI保留侧别、文件及原原因，不创建报告。没有新增WasmError分支。

### 完整名称和四种状态

唯一匹配键是完整导出名，保留空名、空白、大小写、Unicode和控制字符，不trim、
归一化或demangle。不能把kind、index、ordinal或别名成员位置加入匹配键。

| 状态 | 声明关系 | target_index_changed |
| --- | --- | --- |
| added | 仅current有该名称 | null |
| removed | 仅baseline有该名称 | null |
| kind_changed | 双侧有名称，kind不同 | null |
| same_kind | 双侧有名称，kind相同 | UInt数字不同为true，相同为false |

缺失侧声明是null，仅计算字节差时贡献零，不伪造index0。跨kind即使索引数字
相同，target_index_changed仍为null。同名同kind也可能存在不同签名、目标来源
或别名关系，本次不判断这些事项。重命名表现为removed和added，不推断源码身份。

固定边界：仅比较导出名称与种类声明，不评估完整ABI、目标存在性、签名、可达性
或运行行为。index、ordinal和offset只定位各自输入，不能充当跨构建源码身份。
双侧entries、targets、全部别名成员和范围保留，但不跨构建配对(kind,index)组，
不输出别名组增删或风险等级。same_kind不表示“未变化”或“兼容”。

### 实测状态与账本

scripts/test-exports-diff.mjs生成三份合法夹具，各经Node v24.18.0/V8验证一次，
不实例化、不执行。混合比较baseline125 B、current148 B，SHA-256分别为：

```text
bd1aace02a4a11f0b0289d417bc66188b4e265f7f2bc52b880b22e7e31599bf8
6133741122e57000a22b9d741a8820bd5b03cf27975710455a9bb24f0ea4f9fd
```

实际CLI结果：

```text
Names: removed 1; kind_changed 1; added 1; same_kind 5; rows 8
Baseline declarations: 7; current declarations: 7
Baseline export: 56 B = headers 2 B + count 1 B + declarations 53 B
Current export: 64 B = headers 3 B + count 2 B + declarations 59 B
Export delta: 8 B = headers 1 B + count 1 B + declarations 6 B
Declaration delta: 6 B = name encodings 5 B + descriptors 1 B
Name encoding delta: 5 B = length prefixes 1 B + UTF-8 4 B
Descriptor delta: 1 B = kind 0 B + index prefixes 1 B
Non-export: 69 -> 84 B
File delta: 23 B = export 8 B + non-export 15 B
```

removed名称的声明差-10 B，new-feature的added声明差+16 B，其余行差0；行差合计
+6 B。switch从function #0变global #0，只有kind_changed，不拆成两个名称，
其target_index_changed为null。当前段头、count及第一条声明的前缀使用实际
两字节编码。Top1只展示removed行，完整JSON保留8行及双侧各7条声明。

基线function #0的别名成员ordinal为[0,1,2,3,5,6]，当前function #1为
[0,2,3,5,6]；基线有2个声明目标，当前3个。这是双侧保留事实，不是跨构建
目标组匹配或别名组增删判断。

计数满足before7=removed1+kind_changed1+same_kind5，after7=added1+1+5；
rows8=1+1+1+5。所有大小差值为current-baseline，可以为负、零、正。
无export与显式空段可以名称清单相同而相差3 B；same_kind也能因前缀宽度而有
字节差。non_export_bytes=file_size-export_section_bytes，包含文件头、code、
custom及其他段，不是优化空间。声明差不解释函数body、源码修改或gzip收益。

仅重编号样本为140 B，SHA-256：

```text
eaf937ccbd7990ca5ab179333ac690b0f6573b2766b4dc822171242bce47410e
```

通过增加一个前置函数导入构造，导出名称和kind保持不变；6个函数目标索引
由0变1，table #0仍是0。相对原125 B基线，实际为same_kind7，其余三类0，
导出段差0、文件差+15 B（均在non-export）。文本中的实际两行：

```text
"same"  same_kind  function #0  function #1  0  true
"table"  same_kind  table #0  table #0  0  false
```

这验证数字变化不会变成种类变化；它仍不证明跨构建目标身份或完整ABI兼容。

### 输出与使用边界

--diff-exports隐含exports，必须有非空baseline；重复--exports不增加解析。
普通exports配baseline仍返回2。只允许baseline、Top、自身JSON及exports标志，
strict、max-size、预算、HTML、压缩及其他模式在读取前返回2。成功比较（包括
removed和kind_changed）返回0；读取、解析或输出错误1；参数错误2。没有兼容性
门禁。JSON沿用统一目标预检和原生独占创建，不新增writer或事务承诺。

文本行固定按removed、kind_changed、added、same_kind，再按字节差绝对值降序、
完整名称字典序。排序只是展示次序，不是风险分级；Top不截计数、账本、双侧
报告或JSON。文本名称安全转义，JSON保留原值。

JSON独立格式为moonsize-exports-diff/schema_version 1，含baseline/current完整
报告对象、counts、delta（复用ExportsLedger字段表示有符号差值）、文件背景
差值、全部rows及comparison_scope。每行保留name、status、可空baseline/current
完整声明、declaration_bytes_delta和可空target_index_changed。双侧报告不是
序列化字符串，原单文件moonsize-exports格式及字段类型和值保持不变。

```moonbit
compare_exports(Bytes, Bytes) -> Result[ExportsComparison, ComparisonError]
render_exports_diff(ExportsComparison, Int) -> String
render_exports_diff_json(ExportsComparison) -> String
```

新增ExportComparisonRow、ExportsComparisonCounts、ExportsComparison及
Options.diff_exports；见[API迁移](migration-0.5.md)。本地仅3个新组合单测及
4次真实CLI，状态0/0/0/1：混合Top1、完整JSON、仅重编号、已有JSON拒绝且原
字节不变。坏输入侧别在单测验证，未增加第五次CLI。完整u32边界只验证结构
读取，不宣称其目标索引语义有效，也未重测整个exports或LEB错误矩阵。

```sh
moon test --target native exports_diff_wbtest.mbt
node scripts/test-exports-diff.mjs _build/native/release/build/cmd/main/main.exe
```

证据在_build/exports-diff-verification/run-adSfVv/，含三份输入、四份进程日志、
完整exports-diff.json及results.json。本地未运行旧套件、旧CLI、演示、浏览器/
PDF、编译探针或性能基准。CI只追加轻量脚本，旧回归保留，最终SHA整体状态在
推送后核对。版本0.5.1未变，本次未发布Mooncakes。
