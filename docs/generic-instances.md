# MoonBit 泛型实例编码体积

此功能是公开0.5.1之后的源码增量，本次不改版本、不发布Mooncakes。

```sh
moonsize app.wasm --generics --top 20
moonsize app.wasm --generics-json new-generics.json
```

独立模式只允许Top和JSON。`--generics-json`隐含启用模式，要求新的`.json`路径，
继承统一预检和独占创建；已有目标保持原字节。strict及其他分析模式在读取输入前
报参数错误，因为此入口不构图。0表示完成，包括信息不足或零家族；1表示读取、
解析或输出失败；2表示参数错误。Top限制文本家族数，不截断汇总和JSON。

## 识别范围

识别读取FunctionStat.raw_name，不使用display_name或demangle_full的显示结果。
首版接受`_M0F`函数、`_M0M`方法，后接`P`和数字包标识、长度编码的路径组件、
最后的`G...E`类型参数。仅支持真实探针确认的`i`（Int）、`d`（Double）类型编码。
包数字和第一个长度的边界逐一确认；只有整个符号完整解析且无歧义时才分组。
闭包、trait实现、其他包标识、未知类型、未消费后缀或歧义路径均留作未分组。

family_key是保留kind、包、类型与函数路径的完整原始stem，不带类型参数后缀。
保留所有raw_name与raw_type_arguments（含G/E）及解码标签。不同包、函数/方法
不会因为显示名相同而合并；同一个原始符号出现在不同函数index时，分别记录定义
与字节。definition_count与type_encoding_count分别表示定义数、不同原始类型
参数编码数。实例按完整函数索引升序排列，包含前置导入索引的偏移，但只统计本地
函数定义。家族按total_size降序、family_key升序排列。

编译器符号约定不是官方完整规范。family_key只用于当前产物内分组，不保证跨
构建或跨工具链身份稳定。未分组可能包含普通函数、未知编码或不支持的泛型形态，
不能全部称为“非泛型”。编译器已经内联、合并或消除的源码实例不在产物中可见。
零家族只说明没有识别到支持范围内的实例，不证明项目没有泛型。

## 编码账本与名称状态

每个权重使用FunctionStat.total_size：函数体长度前缀加函数体，不包含code段头
及函数数量字段。函数数与编码字节分别核对：

```text
全部本地函数 = 已聚合泛型函数 + 有名称但未分组 + 没有可用名称
```

`name_status`取值：

- `missing`：没有name段。
- `unreadable`：选中的name段无法完整读取，不信任旧解析器保留的部分名称，
  本次聚合将这些定义计入“没有可用名称”。
- `available`：选中的name段结构及函数名称可读；仍可能缺少部分名称，或存在
  不支持的符号，由覆盖账本分别反映。

选段沿用find_sections的规则：存在多个name自定义段时使用最后一个。其他名称
子段作为有边界的不透明字节跳过；这不是完整Wasm名称/类型语义验证。

编码总量不是可消除冗余，不计算“总量减最大实例”。实际优化需修改源码并比较
完整重建产物；本报告不预测重编译或gzip收益。

## 一次真实探针记录

本地平台Windows，Node v24.18.0；moon 0.1.20260915（2e1a46d），
moonc v0.10.13+cbb11c36f，moonrun 0.1.20260915。临时模块名称
`probe/generics`，moon.pkg为`pkgtype(kind: "executable")`。实际源码：

```moonbit
#inline(never)
fn[T] generic_keep(value : T) -> T { value }
struct Holder[T] { value : T }
#inline(never)
fn[T] Holder::get(self : Holder[T]) -> T { self.value }
fn main {
  println(generic_keep(7))
  println(generic_keep(2.5))
  let first : Holder[Int] = { value: 11 }
  let second : Holder[Double] = { value: 3.5 }
  println(first.get())
  println(second.get())
}
```

在该模块目录只执行一次：

```sh
moon build --target wasm --debug --no-strip
```

产物`_build/wasm/debug/build/generics.wasm`：45847字节；SHA-256：
`831729c841ae1c0374bf2f346a2d5aa360710ff446994189f45d7940a54d812f`。
经Node/V8 WebAssembly.validate独立验证一次；后续CLI复用同一文件。
实际识别结果（每行都是产物中的函数定义）：

| index | raw symbol | 类型 | total_size |
| ---: | --- | --- | ---: |
| 38 | `_M0MP25probe8generics6Holder3getGiE` | Int | 8 |
| 39 | `_M0MP25probe8generics6Holder3getGdE` | Double | 8 |
| 40 | `_M0FP25probe8generics13generic__keepGiE` | Int | 5 |
| 41 | `_M0FP25probe8generics13generic__keepGdE` | Double | 5 |

Holder::get家族2个定义/2种编码/16字节；generic_keep家族2个定义/2种编码/10字节。
账本：123个定义 = 4 + 119 + 0；17048编码字节 = 26 + 17022 + 0。
Top1文本只展示Holder::get，JSON保留两个家族四个实例。索引与数字来自这份构建，
不是其他工具链的固定预期。

原始源码、工具链、构建日志及完整原始名称保存在本地
`_build/generic-instances-verification/run-uZPaBd/`，四场景结果在
`_build/generic-instances-verification/run-O6ztYa/`。这些路径是本机证据身份。
复现脚本默认在新目录重新构建一次探针并记录自己的散列，不要求与历史产物相同：

```sh
node scripts/test-generic-instances.mjs _build/native/release/build/cmd/main/main.exe
# 本地已构建时复用，避免第二次构建/独立验证：
node scripts/test-generic-instances.mjs <native-cli> <previous-run>/probe.json
```

脚本只调用分析器四次：真实探针文本、同产物完整JSON、现有无名称最小模块、
已有JSON目标拒绝。新单测集中在generic_instances_test.mbt的`generics:`前缀，
本地仅运行该文件的3个组合测试；没有运行旧功能测试。既有Linux CI仍自动执行
完整回归，本次只追加这一轻量脚本，不新增job或长期演示工程。

## 公开API与JSON

```moonbit
inspect_generic_instances(Bytes) -> Result[GenericInstancesReport, WasmError]
render_generic_instances(GenericInstancesReport, Int) -> String
render_generic_instances_json(GenericInstancesReport) -> String
```

库复用parse_module、collect_function_stats，不调用analyze、建图、retained或
路径查询。报告包含file_size、实际sha256、name_status、recognition_scope、
coverage及完整families。GenericFamily保留family_key、display_name、
definition_count、type_encoding_count、total_size和instances；GenericInstance
保留index、raw_name、raw_type_arguments、type_labels、total_size。

独立JSON格式为`moonsize-generic-instances`、`schema_version: 1`。不嵌入函数体，
不输出未计算的graph_complete。既有路径、图、HTML及其他JSON格式不变；Options
新增generics=false、generics_json=None，见[迁移增量](migration-0.5.md)。
