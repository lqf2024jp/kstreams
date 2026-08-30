# 排查笔记:云端 sink 吞吐只有 100-180/s(本地同配置能到3000+/s)

不是本仓库 benchmark 的一部分,是基于本次 benchmark 里对 `batch.size` /
`consumer.max.poll.records` / fetch 字节上限 的理解,帮用户排查另一套独立环境
(双节点 Kafka Connect + 3节点 MSK)里 JDBC sink 吞吐异常低的问题。这里只记录
**排查思路和进度**,不是这套环境本身的配置文件。

## 现象

| 环境 | Connect 拓扑 | 吞吐 |
|---|---|---|
| "本地"(实为直连) | 单节点 EC2 Connect → 同区 EC2 Postgres | 3000+ 行/秒 |
| "连接环境" | 双节点 Connect(挂 3 节点 MSK)→ **同一个** EC2 Postgres | 100-180 行/秒 |

- source → MSK 的摄入速度两边差不多(240万条约15分钟,~2667条/秒),说明
  source 端和 MSK 本身没问题,瓶颈在 sink(MSK → Postgres)这一段。
- sink 的目标数据库是**同一个** Postgres 实例,所以 Postgres 自身容量不是变量,
  只可能是"写入路径"(网络/连接方式)或"sink 连接器配置/行为"不同。

## 已确认的事实

- 云端:1 个 topic、**1 个分区**、`tasks.max=1`、`insert.mode=insert`、目标表
  **无主键/无索引**。
- 两边 sink connector **版本一致**(排除"云端连接器版本老、没有 batch 支持"这条)。
- `batch.size` 从默认改到 **2048**,吞吐只从 ~100 涨到 ~180,变化很小。
- 连接串加了 **`reWriteBatchedInserts=true`**,变化也不大。

## 已经排除的可能原因(及排除依据)

| 假设 | 排除依据 |
|---|---|
| 并行度/多 task 锁竞争不足 | 单分区决定了 `tasks.max` 再大也只有1个 task 在跑,和"本地"没有本质区别,这条路本身就不成立 |
| upsert 模式行级开销大 | 已确认 `insert.mode=insert`,不是 upsert |
| 目标表有索引拖慢写入 | 已确认目标表无主键/无索引(本仓库自己的 Phase D 实验也证明去索引影响有限,不至于30倍差距) |
| sink 连接器版本太老、没有 batch 支持 | 已确认两边版本一致 |
| PG JDBC 驱动没把 `executeBatch()` 重写成单条多行 INSERT | 已加 `reWriteBatchedInserts=true`,吞吐变化不大,排除或至少不是主因 |
| 单纯 `batch.size` 配置不够大 | 从默认改到2048,吞吐几乎没变,说明"配置的 batch.size"很可能根本没有真正生效 —— 这条线索直接指向下面的头号嫌疑 |

## 当前头号嫌疑:实际拿到的批量,可能根本没变过

本仓库这次 benchmark 的核心结论之一就是:**`batch.size` 只是 sink 想要凑的目标
批量,真正能凑到多少条,上限是 `consumer.max.poll.records`**(默认500)。如果
只调大了 `batch.size`、没有同步调大 `consumer.override.max.poll.records`(还需要
worker 开 `connector.client.config.override.policy=All`,细节见
`BATCH-SIZE-ANALYSIS.zh-CN.md`),那不管 `batch.size` 写多大,单次 `put()` 真正
能拿到的记录数还是被摁在 500(或更低)——这完美解释了"batch.size 从默认改到
2048,吞吐几乎没变"这个现象,因为**实际批量可能压根没变过**。

## 下一步排查清单(按优先级)

1. **【待确认】`consumer.override.max.poll.records`(或 worker 的
   `max.poll.records`)有没有跟着 `batch.size` 一起调大,worker 有没有开
   `connector.client.config.override.policy=All`?**
   如果没有,先补上再重测,预期这一步单独就能带来明显提升。

2. **【待确认】实测落地到 Postgres 的语句,每次真正写了多少行**:
   ```sql
   SELECT query, calls, rows, rows / calls AS avg_rows_per_call
   FROM pg_stat_statements
   WHERE query ILIKE '%目标表名%'
   ORDER BY calls DESC LIMIT 5;
   ```
   - `avg_rows_per_call` 远小于配置的 `batch.size`(个位数/几十)→ 证实批量没
     攒起来,回到第1步查 `max.poll.records`,顺便也要查 MSK 侧的
     `max.partition.fetch.bytes` / `fetch.max.bytes`(单分区 + 到 MSK 有真实
     网络延迟时,这个默认1MB的限制会比本仓库本地零延迟测试时严重得多,因为
     "多来几次 fetch 凑批量"在本地几乎不要钱,在有 RTT 的环境下要花真金白银的
     时间,参考 `REPORT-avro.zh-CN.md` 里的分析)。
   - `avg_rows_per_call` 接近 `batch.size` → 批量本身没问题,瓶颈在"写这一批
     为什么这么慢",转到第3步。

3. **【待确认,问了两次还没拿到答案】双节点 Connect 集群到 Postgres 的网络路径**:
   - 是否和"本地"那台 EC2 在同一个 VPC / 子网 / 可用区?
   - 从 Connect 节点直接 `psql -h <pg host> -c "select 1"` 或 `nc -vz <pg host> 5432`
     实测连接建立耗时,和"本地"那台做对比。
   - 如果 RTT 明显更高(哪怕只是跨可用区的几 ms),而第2步又显示批量确实攒
     起来了但写入还是慢,那就是"批量已经够大,但每批提交都要付网络延迟成本",
     需要看是不是有办法把 Connect 集群挪到离 Postgres 更近的子网/可用区。

4. **如果第1-3步都排查完仍没找到根因**,再往下查:
   - Postgres 侧 `synchronous_commit`、是否开了同步复制(比如 RDS Multi-AZ)、
     磁盘 IOPS 是否打满 —— 这些会让每次 `COMMIT` 本身变慢,且不随 batch.size
     摊薄。
   - Connect worker(双节点)的 CPU/内存配额、GC 情况 —— 资源受限会拖慢
     `poll()`/`put()` 循环本身,和网络、批量大小无关。
   - 连接器日志/DLQ 里有没有大量错误重试 —— 如果个别记录写入失败导致
     Kafka Connect 退化成逐条重试定位坏记录,批量效果会被破坏。

## 结论(截至目前)

已经排除:并行度、upsert、目标表索引、连接器版本、PG 驱动多行重写。
最新的"改 batch.size 几乎无效"这个现象,把头号嫌疑指向**实际批量可能从未真正
变大过**(`max.poll.records` 没跟着调),次号嫌疑是**网络 RTT 放大了未攒够/或
即使攒够了也提交慢的成本**。第1、2步(查 `max.poll.records` 配置 + 用
`pg_stat_statements` 实测真实批量)是接下来最该做、成本也最低的两步,做完就能
把问题锁定在"Kafka 消费侧没攒够批"还是"Postgres 写入侧本身慢"这两个方向之一。
