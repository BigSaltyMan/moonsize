# 普通分析的完整JSON导出

这是公开0.5.1之后的源码增量，使用当前源码构建的native CLI；版本未变，未发布
Mooncakes。本次不新增分析算法，只把普通流程已有结果导出为明确的机器格式。

```sh
moonsize app.wasm --summary-json new-summary.json
moonsize app.wasm --summary-json new-summary.json --top 1 --retained --dead-code
moonsize app.wasm --summary-json new-summary.json --strict --max-size 100KB
```

这是普通文本流程的附加导出，不替代stdout文本，也不把JSON正文打印到stdout。
Top只影响文本；JSON中的段、函数、模块、根、诊断及汇总全部保留。Top不是资源
限制，序列化和SHA-256仍有成本，但不重复解析、分析、建图、解码、压缩或计算
retained，不调用其他inspector。

只允许配合Top、retained、dead-code、strict、max-size。baseline/比较、compress、
HTML、call-graph、experiment、预算配置/输出、data明细及所有独立查询在参数阶段
拒绝，返回2。新目标必须是非空`.json`路径。输出复用统一preflight和原生独占
创建，不能覆盖已有文件、目录或链接别名；未新增多文件事务保证。

顺序与退出码：输入/分析失败返回1且不写报告；strict不完整返回3，在预检查和
写入前拒绝；非strict不完整仍导出全部诊断；输出失败返回1；max-size超限仍先
保存解释报告，再由原门禁返回3。JSON不包含预算结论，已有文本和退出语义不变。

## 格式与字段

根对象固定为format=`moonsize-summary`、schema_version=`1`，以及input、summary、
sections、functions、modules、model。没有时间戳，不序列化输入bytes、Map/Set布局、
完整调用边、gzip或其他未测量指标。边界说明可提到gzip，但没有gzip测量字段。
需要完整调用边时另用`--call-graph`，不能与本选项组合。

### input和summary

input含file_size（字节整数）、sha256（完整文件摘要字符串）、wasm_version（整数）。
SHA-256由renderer使用现有函数计算一次，未给每个函数重复计算摘要。

summary所有字段均为整数：

| 字段 | 含义 |
| --- | --- |
| wasm_header_bytes | Wasm头部8字节 |
| section_count / section_bytes | 全部物理段实例数 / 完整段编码总量 |
| defined_function_count | 全部本地定义数，不含导入 |
| defined_body_bytes | 本地locals及指令编码总量 |
| defined_prefix_bytes | 本地函数体长度前缀总量，使用实际宽度 |
| defined_encoded_bytes | 本地完整条目编码总量 |
| reachable_defined_count / unreachable_defined_count | 模型可达 / 不可达本地定义数 |
| reachable_encoded_bytes / unreachable_encoded_bytes | 对应本地条目编码量 |
| module_count | 按既有符号归属标签分组的数量 |

账本：

```text
file_size = wasm_header_bytes + sum(section.total_size)
section.total_size = section_header_bytes + payload_size
defined_encoded_bytes = defined_prefix_bytes + defined_body_bytes
sum(module.encoded_bytes) = defined_encoded_bytes
sum(module.function_count) = defined_function_count
defined_function_count = reachable_defined_count + unreachable_defined_count
defined_encoded_bytes = reachable_encoded_bytes + unreachable_encoded_bytes
```

### sections、functions和modules

sections按原文件顺序保留每个实例，包括同名重复custom段。每项含ordinal（从0
开始）、id（整数）、kind（现有小写段名）、offset、payload_size、total_size、
section_header_bytes（整数），以及custom_name_display（字符串或null）。后者直接
沿用Section.custom_name显示标签，不承诺严格UTF-8身份验证，也不额外读取name；
严格编码明细请用`--metadata`。

functions仅有本地定义，按完整index升序，包含前置函数导入占用的编号：

| 字段 | 类型 / 含义 |
| --- | --- |
| index | 整数，完整函数index |
| name / raw_name | 显示字符串 / 可空原始字符串，保留原始内容 |
| module_name | 既有FunctionStat归属标签字符串 |
| offset | 整数，body长度前缀的file offset，不是首条指令地址 |
| body_size / prefix_size / total_size | 整数字节数，total=body+prefix |
| model_reachable / model_root / model_indirect_candidate | 当前Analysis中的布尔结果 |
| model_retained | 既有结果对象，缺项为null，不补零或重新计算 |

model_retained对象含own_encoded_bytes、dominated_encoded_bytes、
other_dominated_function_count，均为整数。dominated_encoded_bytes直接采用既有
RetainedSize.retained，**包含自身**；other_dominated_function_count直接采用
retained_functions，**不包含自身**。缺项即使是可达函数也保持null。

modules按完整module_name字典序升序；每项含module_name字符串、function_count、
body_bytes、prefix_bytes、encoded_bytes整数，以及升序完整function_indices数组。
这些是符号标签分组，不证明精确源码包或第三方依赖身份。导入函数没有本地body，
不会作为0字节定义加入functions或modules，但导入根仍会出现在model.root_indices。

### model

graph_complete为布尔；unresolved_count是无静态候选的普通/尾间接调用点数；
diagnostic_count是诊断条目数，两者独立，不能把后者称为调用点数。
diagnostics按现有规则排序并复用原序列化，保留code、caller、offset、opcode、
type_index、table_index及已有source证据；null仍为null，原先缺失的source不
虚构。新格式额外给出共享说明逻辑生成的reason字符串，不改其他报告格式。
source对象的caller/opcode可为null，offset是风险来源，不是间接调用位置。

root_indices为完整升序整数数组；modeling_scope和retained_scope为英文边界说明。
graph_complete=true只表示当前范围内未发现缺口，不是完整Wasm认证。模型不可达
不证明实际未使用或可安全删除；retained集合可能重叠，不能把全部retained相加。
函数/模块体积包含于段视图，不能把这些视图重复相加，也不预测重编译或gzip收益。

## 机器消费

```js
import fs from 'node:fs';
const report = JSON.parse(fs.readFileSync('new-summary.json', 'utf8'));
if (report.format !== 'moonsize-summary' || report.schema_version !== 1) {
  throw new Error('Unsupported summary format');
}
console.log(report.functions.map(f => [f.index, f.total_size, f.model_retained]));
console.log(report.modules.map(m => [m.module_name, m.function_indices, m.encoded_bytes]));
console.log(report.model.graph_complete, report.model.diagnostics);
```

不要通过文本的Top行推断全量；不要把null当成0。名称中的引号、换行、CJK从JSON
还原后保持原值。对同一个Analysis重复渲染逐字节一致；renderer对数组副本排序，
不重排调用者持有的stats、段或诊断。

## API迁移

新增render_summary_json(Analysis)->String，CLI传入普通流程中的同一个Analysis。
只增加renderer和Options.summary_json=None；默认值由Options::default提供，外部
手工构造Options需补字段。不增加公开分析类型，不改旧签名、WasmError、依赖或
其他JSON格式。详见[迁移说明](migration-0.5.md)。

## 本次实际验收

2026-10-25在Windows、Node v24.18.0/V8 13.6.233.17-node.50运行。完整样本124字节，含
一个函数导入、4个本地定义、导入/本地导出根、两个同名custom段和带引号/换行/
中文的名称；另一个69字节样本同时有静态候选、导出表和table.set。
两个合法fixture分别由Node/V8验证一次，不实例化、不执行。输入SHA-256：

```text
full     ad29b620fb5bb5b2675c81d54bd108c6daecc37d52ad1d6509eab04ac58d0e74
dynamic  d979f0c9d1578f3ed6d972c22d523518bbad5fc2b7bbeb050778a88b6f5be15d
```

完整样本：文件124=8头部+116段编码，共8个物理段。4本地定义的编码16=11body
+5前缀；可达2/9字节，不可达2/7字节；4=2+2、16=9+7。模块(unnamed)、alpha、z
分别为3、4、9字节，合计16；成员[4]、[2]、[1,3]共4个定义。根[0,1]保留导入
index0，但functions仅有[1,2,3,4]。root index1的own5、dominated9、other count1；
index2的own4、dominated4、other count0；不可达两项retained为null。

下面是实际输出的summary对象，所有量为JSON数字：

```json
{
  "wasm_header_bytes": 8,
  "section_count": 8,
  "section_bytes": 116,
  "defined_function_count": 4,
  "defined_body_bytes": 11,
  "defined_prefix_bytes": 5,
  "defined_encoded_bytes": 16,
  "reachable_defined_count": 2,
  "unreachable_defined_count": 2,
  "reachable_encoded_bytes": 9,
  "unreachable_encoded_bytes": 7,
  "module_count": 3
}
```

| 真实CLI场景 | 精确退出码 | 文件结果 |
| --- | ---: | --- |
| Top1、retained、dead-code、summary-json、max-size 0B | 3 | 完整JSON已保存，4函数/3模块/8段不截断 |
| 动态表样本非strict | 0 | 保存全部诊断与来源 |
| 同一样本strict | 3 | 未创建新的JSON |
| 正常输入写已有目标 | 1 | 原文件字节不变，无错误成功提示 |

动态样本unresolved_count=0、diagnostic_count=2、graph_complete=false。两条诊断
都指向function0/file offset56的call_indirect（type0/table0）；runtime来源为
function0/offset63/table.set，export来源offset38，caller/opcode为null。静态候选
index1仍标记true，候选非空不掩盖风险。这是两条原因，不是两个无候选调用点。

可复验脚本为scripts/test-summary-json.mjs，每次创建新目录，严格只调用分析器
四次。本地完整JSON、dynamic JSON、输入、日志、散列和记录保存在
`_build/summary-json-verification/run-697SsH/`；CI不会覆盖这份本地证据。原始JSON文件名为summary.json和dynamic.json。
本地仅3个新组合单测、四次CLI及必要接口/格式/native检查和一次release构建；
未跑旧套件、旧CLI、演示、浏览器/PDF或性能基准。旧回归由目标提交Linux CI执行。
