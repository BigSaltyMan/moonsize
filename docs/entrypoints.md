# 导出入口依赖体积

此功能是公开0.5.1之后的源码增量。本次不改版本、不发布Mooncakes；从当前源码
构建native CLI后使用：

```sh
moonsize app.wasm --entrypoints --top 20
moonsize app.wasm --entrypoints-json new-entrypoints.json
moonsize app.wasm --entrypoints --strict
```

独立模式只允许Top、入口JSON和strict，其他模式在读取输入前报参数错误。
JSON隐含启用入口分析，要求新的`.json`路径。退出码：0完成（包括没有函数导出），
1读取/解析/索引/输出错误，2参数错误，3严格模式拒绝不完整图。strict先检查图
诊断，再做文件预检和独占创建；拒绝不创建报告。新输出沿用既有非事务边界。

## 集合关系与账本

只有函数导出是入口，memory/table/global/tag等导出单独列出，不套用函数体积。
同一函数索引的多个导出名是别名，归为一个组；保留全部名称，分别统计名称数量
和唯一入口组数量。组ID使用完整函数索引，包含前置导入。

图只构建一次，每个唯一入口遍历一次；start和当前模型保守保留的全部element
函数再合并遍历一次，包括active、passive、declarative等来源。函数即使同时被
导出，也不从这些根中移除。沿用已有解析器，element来源标签中的
`passive-or-declarative`不声称进一步区分这两种编码。

一个函数只被入口i到达，且不被start/element根到达时，其编码字节属于i的
`exclusive_model_bytes`；被其他组或其他根也到达时属于`shared_model_bytes`。
各组与全局分别核对：

```text
入口可达编码量 = 该入口模型独有编码量 + 该入口模型共享编码量
全部本地函数编码量 = 函数导出可达并集编码量 + 非导出可达编码量
函数导出可达并集编码量 = 各组独有编码量之和 + 全局共享函数编码量（每函数一次）
```

每个权重是本地函数total_size，含函数体长度前缀，不含code段头和数量字段，
也不含data、name、type等其他段。导入函数没有本地函数体，节点encoded_size为
null，可以计入可达导入数量；null不表示宿主调用没有成本。

共享信息由唯一函数归属表生成。每条记录保留节点身份、所属入口索引及是否被
其他根到达；入口组保留完整可达索引，不重复存储节点。共享本地函数列表只存
索引，按编码量降序、索引升序排列；入口同样按可达编码量降序、索引升序排列。
归属组索引、可达索引和其他根索引升序，别名按原export顺序保留。

Top分别限制两张文本表的行数，不截断别名、汇总、库结果或JSON。它不是资源
限制；唯一入口越多，需要的可达性计算越多，没有固定成本或性能承诺。

## 实际共享样本

`scripts/test-entrypoints.mjs`构造一个166字节合法模块，仅用Node/V8独立验证
一次。输入SHA-256：
`9a8bb7f9c1f0164365eb5a495f038f152a20b2360ea08bb820bcd3c4a0969ff6`。
本地输出在`_build/entrypoints-verification/run-3bSGHG/`，包含输入、各次日志、
完整JSON与results.json；这是本机证据位置，CI会在新目录复现。

原始导出有A、含引号/反斜杠/换行/中文的别名、B和memory。3个函数导出名归为
2组：A及其别名指向#1，B指向#2，memory不计函数体积。实际结果：

| 入口索引 | 可达索引 | 本地数 | 导入数 | 可达B | 模型独有B | 模型共享B |
| ---: | --- | ---: | ---: | ---: | ---: | ---: |
| 1 | 0, 1, 3, 4, 5 | 4 | 1 | 26 | 13 | 13 |
| 2 | 2, 3 | 2 | 0 | 10 | 5 | 5 |

共享本地函数按实际输出顺序：

| 索引 | 编码B | 所属入口组 | start/element可达 |
| ---: | ---: | --- | --- |
| 3 | 5 | 1, 2 | false |
| 5 | 5 | 1 | true |
| 4 | 3 | 1 | true |

#3有自调用环，遍历正常结束。#0是导入函数，编码大小null；#5既是start也是
passive element根，#4来自declarative element，且可由#5到达。因此#4、#5即使
只属于入口组1，也不算其独有。另一个新单测把start设为已导出的#1，确认该组
模型独有量降为0；没有从其他根中删掉已导出的函数。

166字节文件内，6个本地定义共34编码字节，5个本地定义被函数导出到达：

```text
All local: 34 B = function-export union 31 B + not export-reachable 3 B
Export union: 31 B = sum of group-exclusive 18 B + shared (counted once) 13 B
```

26+10=36既不是并集31，也不是文件166；各组共享量13+5也不等于全局共享13。
Top1文本显示一组和一个共享本地函数，仍保留组内全部别名；JSON保留两组及七个
函数节点的完整信息。#1在文件偏移98的call_ref保留模块级缺口；先前ref.func
记录的是取引用，不宣称call_ref的运行目标已求解。

## 模型边界

“独有”只是当前引用模型内的集合关系。间接调用候选与ref.func不是运行时必然
调用，不做执行频率分析。完整模块诊断保留，但不一定涉及每个入口。graph_complete
或strict成功均不证明完整Wasm语义。未被函数导出到达不等于死代码；即使没有
函数导出，也可能有start/element根。各入口可达量、共享量不能相加当作模块大小。
本报告不预测删除入口后的真实减量、重编译或gzip收益。

## 公开API及JSON

```moonbit
inspect_entrypoints(Bytes) -> Result[EntrypointsReport, EntrypointsError]
render_entrypoints(EntrypointsReport, Int) -> String
render_entrypoints_json(EntrypointsReport) -> String
describe_entrypoints_error(EntrypointsError) -> String
```

复用parse_module、函数清单path_inventory、export/start/element解析、build(data)
及迭代reachable_from_roots。不会调用analyze/retained，也不逐入口解析或构图。
函数导出、其他根及全部图边均检查函数索引范围；错误使用实际名称/序号/指令
位置。非函数导出的索引属于各自索引空间，本入口不提供完整类型/语义验证。

报告包括输入大小及实际SHA-256、入口与名称数量、其他导出、入口组、函数归属、
其他根及来源、共享本地索引、全局账本、graph_complete、完整diagnostics与scope。
新增EntrypointGroup、EntrypointFunction、EntrypointsLedger、EntrypointsReport、
EntrypointsError；Options新增entrypoints=false、entrypoints_json=None。
[迁移增量](migration-0.5.md)不修改旧公开签名或原有报告格式。

JSON独立使用`format: moonsize-entrypoints`、`schema_version: 1`。`functions`
按完整函数索引排列，节点仅在该表存一份；其他数组中的函数/入口索引用于引用。
没有源码归属推断、HTML、入口预算、跨构建匹配或删除收益字段。

## 定向验证

本地只运行entrypoints_wbtest.mbt内`entrypoints:`前缀的3个组合测试，覆盖别名、
共享与其他根、导入、空入口、坏索引、环、排序、Top/JSON及参数约束。native检查、
格式、接口生成及一次release构建属于编译验证，不是运行旧测试。

```sh
moon test --target native entrypoints_wbtest.mbt
node scripts/test-entrypoints.mjs _build/native/release/build/cmd/main/main.exe
```

脚本只启动分析器四次：文本Top1、完整JSON、strict3且无报告、已有JSON1且字节
不变。不重复路径/链接保护矩阵，不生成源码探针，不跑本地旧套件或视觉/性能
验收。CI只追加同一轻量脚本，旧回归仍由既有CI执行，最终状态按目标SHA核对。
