# 宿主导入依赖与编码开销

这是公开0.5.1之后的源码增量，使用当前源码构建的native CLI；本次版本不变，
不发布Mooncakes。本入口只列Wasm文件声明的宿主接口及其**导入声明编码字节**。

```sh
moonsize app.wasm --imports --top 20
moonsize app.wasm --imports-json new-imports.json
```

JSON隐含启用。独立模式只允许Top和自身JSON，strict、baseline、预算及其他模式
在参数阶段拒绝（返回2、读取输入之前）。目标要求新的`.json`文件，接入既有
统一预检和原生独占创建。已有文件不覆盖；不增加多文件事务或其他并发保证。
0表示报告成功，包括空结果；1表示读取、结构、暂不支持编码或输出/保护失败。
核心import段没有metadata可选内容的partial成功规则，解析失败不输出半份清单，
也不创建JSON。

## 首版描述符范围

按[import编码](https://webassembly.github.io/spec/core/binary/modules.html#import-section)
和[外部类型编码](https://webassembly.github.io/spec/core/binary/types.html#external-types)
读取名称及描述符，支持以下明确子集，不声称覆盖所有Wasm特性：

| kind | 名称 | 本入口支持 |
| ---: | --- | --- |
| 0 | function | u32 type_index，仅声明值，不解析签名 |
| 1 | table | 短编码funcref/externref，32位limits flags 0/1 |
| 2 | memory | 32位limits flags 0/1，以及有maximum的shared flags 3 |
| 3 | global | i32/i64/f32/f64/v128/funcref/externref，mutability 0/1 |
| 4 | tag | attribute 0、u32 type_index |

limits先检查flags，再按支持的宽度读取数值；minimum/maximum用UInt，不通过
有符号Int中转。有maximum时检查minimum不超过maximum；shared无maximum、
非法mutability、非零tag attribute均报告位置及具体原因。typed reference、
其他GC形态、memory64/table64和其他flags明确暂不支持；不会先按错误宽度读完，
再猜测边界。未知kind没有可跳过长度，立即失败，不试图恢复下一条。

入口复用parse_module的外层检查，只深入读取import段，按声明数量增量读取，
并要求恰好耗尽payload；不会按不可信数量预分配巨大数组。不调用analyze、
建图、函数体统计或路径查询，不重构旧count_imported_functions/skip_import_desc。
这里不做完整类型、memory页数上限、引用索引或实例化合法性验证。

## 身份、索引和范围

每条声明保留ordinal、kind、kind_index、module、field、完整encoding、两名称
encoding、descriptor及type_index。库字段用module_name避开当前工具链保留字，
JSON使用module。module/field严格UTF-8读取，完整保留空白、大小写、点号、空名
及Unicode，不trim或拆分。损坏名称直接报位置，不用替代字符充当身份。

- ordinal是全部import声明的顺序。
- kind_index在该种类的导入索引空间独立计数，排序不改变它。
- type_index只用于function/tag，完整承载u32；其余为null。它是声明值，不保证
  指向有效类型，也不是完整函数签名。

重复module/field分别保留；同一模块名的汇总保留全部ordinal和各kind数量，不
把同名条目合并。模块名不会被解释为包、路径、网址、权限或运行环境标识。

所有范围是原文件的半开区间`[offset, offset + size)`，不是运行时地址。先经
有界Reader验证读取范围，再使用游标计算实际大小；没有先做不受检查的末尾加法。
名称encoding包含长度前缀和UTF-8字节，descriptor包含kind字节。合法非最短LEB
保留实际宽度，不重编码成最短形式后再计费。

## 实测样本和闭合账本

`scripts/test-imports.mjs`生成152字节的混合样本，SHA-256：
`d49477164139d573f94157fa29ae1cf8af9ef138587f81a8969c041ed4146aa9`。
含必要的`() -> ()`类型、9条导入，function/table/memory/global各2条、tag 1条；
Node v24.18.0/V8仅独立验证一次，不实例化或执行。文本Top1实际输出：

```text
Import section bytes: 138 B = section header 3 B + count prefix 2 B + declarations 133 B
Declaration encoding bytes: 133 B = module names 64 B + field names 39 B + descriptors 30 B
Module-name encodings: 64 B = length prefixes 10 B + UTF-8 54 B
Field-name encodings: 39 B = length prefixes 10 B + UTF-8 29 B
```

模块汇总在Top1下仍完整，按条目字节降序、完整名称升序排列：

| module（JSON转义） | 声明数 | 条目编码B | 全部ordinal |
| --- | ---: | ---: | --- |
| `"env"` | 4 | 51 | 0, 1, 2, 5 |
| `" spaced.module "` | 2 | 43 | 6, 7 |
| `"宿主"` | 2 | 24 | 3, 8 |
| `""` | 1 | 15 | 4 |

模块合计`51 + 43 + 24 + 15 = 133`，段头和count单列，不分摊到各模块。文件其余
14字节是模块头和type段，不混入导入账本。前三条声明展示独立索引空间：

| ordinal | kind | kind_index | module / field | file offset | 编码B |
| ---: | --- | ---: | --- | ---: | ---: |
| 0 | function | 0 | env / same | 19 | 14 |
| 1 | table | 0 | env / table | 33 | 15 |
| 2 | function | 1 | env / same | 48 | 11 |

第一条名称长度和type_index均使用两字节合法非最短编码；两条env/same分别保留。
文本条目按编码大小降序、ordinal升序，Top1显示ordinal6（22字节），JSON仍按
原始声明顺序保存全部9条。换行、引号及控制字符在文本中转义，JSON还原后保留
原名称。`宿主`按6个UTF-8字节核算，不按两个字符核算。

父子项是分解，不能将138字节的import段与其133字节条目再次相加。无import段时
section/count_encoding为null且账本为零；显式零条目段保留实际段头和count前缀。

## API、错误和JSON

```moonbit
inspect_imports(Bytes) -> Result[ImportsReport, WasmError]
render_imports(ImportsReport, Int) -> String
render_imports_json(ImportsReport) -> String
```

新增ImportByteRange、ImportLimits、ImportDeclaration、ImportKindCounts、
ImportModule、ImportsLedger和ImportsReport。Options新增imports=false与
imports_json=None。新增WasmError::InvalidImportEncoding(offset, reason)，外部
穷举匹配需处理该分支；既有截断、LEB溢出和尾随字节错误继续复用。旧接口、
默认分析、计数函数和报告格式不变，见[接口迁移说明](migration-0.5.md)。

JSON独立使用`format: moonsize-imports`、`schema_version: 1`，包含输入实际大小、
SHA-256、支持范围、完整账本、模块汇总和声明顺序的全部条目。每项保留范围、
名称前缀/UTF-8字节、类型索引，以及适用的limits/value_type/mutability。未解析
type段，不编造签名；u32高位值不会变负数。无graph_complete或优化收益字段。

## 定向验证和边界

本地只运行imports_wbtest.mbt中`imports:`前缀的3个组合测试，以及脚本的四次
真实CLI调用：混合样本文本Top1、同样本完整JSON、memory64拒绝且不创建JSON、
已有JSON拒绝且原字节不变。memory64报`import encoding at offset 14: unsupported
memory64 limits flags 4`并返回1，不笼统称其为无效Wasm。

```sh
moon test --target native imports_wbtest.mbt
node scripts/test-imports.mjs _build/native/release/build/cmd/main/main.exe
```

证据在`_build/imports-verification/run-OXjhpk/`，含两份输入、四次日志、完整JSON
和results.json；这是本机证据位置，CI在新目录复现。单测另检查空结果、完整u32
数值、转义、失败位置和参数约束；超大type_index样本仅证明结构读取，不宣称
语义有效。没有在本地运行旧测试、旧CLI、源码探针、演示、浏览器/PDF或性能基准。
CI复用native构建只追加同一脚本，原有回归不变；提交后核对确切SHA整体结果。

导入声明不等于运行时实际调用，不证明权限使用或环境兼容性；声明编码字节
不是宿主实现、依赖包或下载体积，也不预测删除、重编译或gzip收益。
