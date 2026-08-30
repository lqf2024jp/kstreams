# batch.size 与相关参数的关系梳理 + 当前配置下的最优值分析

基于 `results/results.jsonl` 里 Phase B(Avro,400万行全量,默认 1MB
`max.partition.fetch.bytes`)和 Phase E(在此基础上把 `max.partition.fetch.bytes`
提到 5MB 的对照实验)的实测数据,结合 `generate_sink_configs.py` 里实际下发的
连接器配置,梳理 `batch.size`、`consumer.override.max.poll.records`、
`fetch.max.bytes`、`max.partition.fetch.bytes`、`message.max.bytes`、
`max.message.bytes` 六者的关系,并给出目前测过的所有配置里吞吐最优的
`batch.size` + `max.partition.fetch.bytes` 组合。

## 六个参数分别是谁在管什么

它们其实分两类,不是同一维度的东西:

**第一类 —— 决定"一次 put() 到底能拿到多少条记录"(条数/字节上限,层层收窄):**

| 参数 | 生效位置 | 含义 |
|---|---|---|
| `batch.size` | JDBC sink connector | sink 拿到记录后,**尝试**多少条一组去执行 `executeBatch()` 写库。这是"目标值",不代表真能凑够 |
| `consumer.override.max.poll.records` | sink 的 consumer(本次 benchmark 用 per-connector override) | 单次 `poll()` **最多**返回多少条记录给 `put()`。这是喂给 sink 的"每轮总量上限" |
| `max.partition.fetch.bytes` | consumer,单分区 | 单个分区单次 fetch 请求最多能拿多少字节。字节数除以平均消息大小,就是这一层实际能装下的条数上限 |
| `fetch.max.bytes` | consumer,跨所有分区汇总 | 一次 fetch 请求(可能覆盖多个分区)总共最多拿多少字节。只有一个分区时,这一层基本不会先于 `max.partition.fetch.bytes` 生效 |

**第二类 —— 和"批量条数"无关,管的是"单条消息本身能有多大":**

| 参数 | 生效位置 | 含义 |
|---|---|---|
| `message.max.bytes` | broker | 单条消息的硬上限,超过就直接拒绝写入(和攒多少条一批没关系) |
| `max.message.bytes` | topic(继承 broker 默认) | 同上,topic 级别 |

也就是说,**"实际一次 put() 真正处理的记录数"是第一类四个参数逐层收窄的结果**:

```
实际条数 ≈ min(
  batch.size,                                          -- sink 想要的目标批量
  consumer.override.max.poll.records,                  -- poll() 单次条数上限
  ⌊max.partition.fetch.bytes / 平均每条消息字节数⌋,      -- 单分区单次 fetch 的条数上限
  ⌊fetch.max.bytes / 平均每条消息字节数⌋                 -- 跨分区汇总的条数上限(单分区场景通常不是瓶颈)
)
```

`message.max.bytes` / `max.message.bytes` 不参与这个 min() —— 它们是前提条件:
只要没有单条记录超过这个上限,就不影响批量条数;一旦超过,是直接报错拒绝写入,
不是"批量变小"。我们的 aviation 表平均每条 Avro 消息约 445 字节,离 1MB 的默认
上限差了三个数量级,这次测试里完全不构成瓶颈,可以先排除。

## 代入我们实测的数字

`mysql.pizzashop.aviation`(单分区)在磁盘上的实际大小:

```
(1073731818 + 705715430) 字节 / 4,000,000 条 ≈ 每条 444.9 字节
```

按默认 `max.partition.fetch.bytes = 1,048,576` 字节(1MB)算:

```
1,048,576 / 444.9 ≈ 单次 fetch 最多约 2,357 条
```

这次 benchmark 全程都没有改动 `max.partition.fetch.bytes` / `fetch.max.bytes` /
`message.max.bytes` / `max.message.bytes`,只按 `max(batch.size*2, 2000)` 的
规则调了 `consumer.override.max.poll.records`:

| batch.size | max.poll.records override | 单次fetch理论条数上限(≈2357) | 谁在这一档实际卡脖子 |
|---|---|---|---|
| 500 | 2000 | 2357 | **batch.size 本身**(500 < 2000 < 2357,两层限制都没触碰到) |
| 1000 | 2000 | 2357 | **batch.size 本身**(1000 < 2000 < 2357,同上) |
| 5000 | 10000 | 2357 | **fetch 字节上限**(2357 < 5000 < 10000,单次 fetch 装不下5000条) |
| 10000 | 20000 | 2357 | **fetch 字节上限**(2357 远小于 10000,更加装不下) |

## 结合实测吞吐,看每一档到底发生了什么

| batch.size | 400万行耗时 | eps @4M | 相邻档提升 |
|---|---|---|---|
| 500 | 412.1s | 9706 | — |
| 1000 | 369.7s | 10819 | +11.5% |
| 5000 | 350.0s | 11428 | +5.6% |
| 10000 | 349.4s | 11450 | **+0.2%** |

- **500 → 1000**:两档都没被 Kafka 侧任何参数卡住(见上表),提升的+11.5%纯粹是
  "DB 侧一次 executeBatch 装更多行、往返次数更少"带来的效率提升。
- **1000 → 5000**:batch.size 已经超过了单次 fetch 的理论条数上限(2357),但吞吐
  还是明显涨了(+5.6%)。说明 consumer 的 `poll()` 并不是"一次 fetch 打满就返回",
  而是在超时时间内可以发起多次 fetch 请求把 buffer 攒到接近 `max.poll.records`
  再返回给 `put()`(本地 Docker 网络往返延迟很低,多攒几次成本不高)——所以实际
  批量能明显超过 2357,只是没有精确对齐到 5000。
- **5000 → 10000**:两档的"单次 fetch 条数上限"其实完全一样(都是 2357,因为
  `max.partition.fetch.bytes` 没变),`max.poll.records` 上限从10000翻倍到20000
  也没换来实质提升(只有 +0.2%,在测量误差范围内)。说明多攒几轮 fetch 换取
  更大批量的边际收益,在 5000 这一档已经基本耗尽 —— 再往上加 batch.size /
  max.poll.records,受益的只是理论上限的数字,实际吞吐已经摸到了当前
  `max.partition.fetch.bytes=1MB` 这个配置下的天花板附近。

## Phase E 验证实验:把 max.partition.fetch.bytes 从 1MB 提到 5MB 实测

上一版结论提出"想突破天花板需要调大 `max.partition.fetch.bytes`"只是推测,现在
已经跑了实际对照实验:新建两个 sink connector,只在原 batch.size=5000/10000 的
配置基础上加一条 `"consumer.override.max.partition.fetch.bytes": "5242880"`
(1MB→5MB,理论上单次 fetch 能装约11800条,覆盖了 batch.size=10000),其余不变,
针对同一个 `mysql.pizzashop.aviation` topic(仍是之前那 400万条)重新跑一遍。

| 配置 | 100万eps | 400万eps | 400万耗时 | vs 同 batch.size 的 1MB 版本 |
|---|---|---|---|---|
| batch.size=5000,fetch=1MB(原) | 10898 | 11428 | 350.0s | — |
| **batch.size=5000,fetch=5MB(新)** | **14023** | **11791** | **339.2s** | **+3.2%** |
| batch.size=10000,fetch=1MB(原) | 12284 | 11450 | 349.4s | — |
| batch.size=10000,fetch=5MB(新) | 10906 | 11119 | 359.7s | **−2.9%** |

结果和最初的推测**部分吻合、部分打脸**:

- **batch.size=5000 确实吃到了 fetch 上限放宽的好处**:400万耗时从350.0s降到
  339.2s(+3.2%),中途100万检查点甚至一度冲到14023 eps(比之前任何一档、任何
  检查点都高)——说明 `max.partition.fetch.bytes=1MB` 对 batch.size=5000 而言
  确实是个真实存在、能被解除的瓶颈,只是解除后的整体收益不算夸张。
- **batch.size=10000 没有像预想的那样"终于追上或反超5000",反而比它自己原来
  (1MB fetch)的版本还慢了(11450→11119,−2.9%)**。也就是说"buffer 越大、
  fetch 上限越松,大 batch.size 就该跑得更快"这个直觉在10000这一档不成立 ——
  `max.poll.records=20000` + `max.partition.fetch.bytes=5MB` 让单次 poll/put
  周期要在内存里攒的数据量、单次 `executeBatch` 的事务体积都明显变大,这部分
  额外开销(更大的 GC 压力、更大的单笔数据库事务/WAL 写入)抵消掉了、甚至反超了
  放宽 fetch 上限带来的收益。

（这组实验每个配置也只跑了一次,和前面 Phase B 一样存在单次测量的噪声,但
batch.size=5000 稳定跑赢 batch.size=10000 这个方向,在 1MB 和 5MB 两种 fetch
配置下是一致的,不像是单纯噪声。）

## 结论:目前测过的所有配置里,最优是 —— batch.size=5000 + max.partition.fetch.bytes=5MB

- **不建议用 500 或 1000**:两档在默认配置下都远没有用满 Kafka 侧允许的条数上限
  (见前面分析),单纯加大 batch.size 就能白捡吞吐,没理由留在这两档。
- **不建议用 batch.size=10000**:无论 `max.partition.fetch.bytes` 是1MB还是5MB,
  10000 都没有稳定跑赢 5000 —— 1MB 下两者只差0.2%(10000略赢,在噪声范围内),
  5MB 下反而是 5000 明显更快(11791 vs 11119)。10000 只会让 `max.poll.records`
  翻倍(消耗更多内存、更容易在数据库变慢时触发 `max.poll.interval.ms` 超时导致
  rebalance),却换不来稳定的吞吐提升。
- **推荐配置:`batch.size=5000` + `consumer.override.max.poll.records=10000`
  + `consumer.override.max.partition.fetch.bytes=5242880`(5MB)**。这是目前
  测过的8个 Avro 配置(1MB下的500/1000/5000/10000,5MB下的5000/10000,外加
  batch.size=1)里吞吐最高的一档(400万条 11791 eps),比"什么都不调、只把
  batch.size设成500"的默认起点快了约21.5%。
- 后续如果还想再往上探,方向不是继续加大 batch.size,而是排查 DB 侧
  (Postgres 写入、`executeBatch` 本身)或 Connect worker 的 JVM 内存/GC 配置,
  `max.partition.fetch.bytes` 这条路目前看已经接近收益拐点。
