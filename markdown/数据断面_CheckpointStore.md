这就进入**生产系统设计**了。

如果是我设计，我**绝对不会删除 Marker**。

因为：

> **Marker 本身就是审计证据（Audit Evidence）。**

每天都要生成断面，每天都要给运营、DBA、审计人员出报告，那么**历史记录必须保留**。

------

# 我会把系统拆成三个层次

```text
                Kafka Streams
                      │
          ┌───────────┴───────────┐
          │                       │
     StateStore              Audit Topic
     (运行状态)               (历史记录)
```

------

## 第一层：StateStore（运行状态）

这里只保存：

**正在等待的 Batch。**

例如：

```text
CheckpointId      Status

JOB1-20260712     WAITING

JOB2-20260712     WAITING
```

一旦：

```text
READY
```

就：

**从 StateStore 删除。**

因为：

它已经不需要参与后续计算。

StateStore 的职责：

> **帮助算法继续运行。**

不是保存历史。

------

## 第二层：Audit Topic（永久保存）

例如：

```text
snapshot-audit-topic
```

每一个 Batch：

最终：

发送一条：

```json
{
  "checkpointId":"JOB1-20260712",

  "batchId":"JOB1",

  "status":"READY",

  "decisionTime":"2026-07-12T13:00:03",

  "watermarkSequence":1005,

  "topics":[...],

  "validation":{...}
}
```

Kafka：

保留：

例如：

```text
365 天
```

以后：

任何时候：

都能：

重新消费。

------

# 第三层：Audit DB

我更推荐：

Audit Topic：

Sink：

到：

```text
PostgreSQL
```

例如：

```text
snapshot_audit
```

表：

```sql
CREATE TABLE snapshot_audit
(
    checkpoint_id varchar(100),

    batch_id varchar(50),

    watermark_sequence bigint,

    watermark_timestamp timestamp,

    decision_time timestamp,

    result varchar(20),

    report jsonb
);
```

这里：

```text
report
```

直接：

保存：

整个：

JSON。

------

# 然后每天报表怎么办？

例如：

每天：

08:00

跑：

```sql
SELECT *

FROM snapshot_audit

WHERE decision_time >= CURRENT_DATE;
```

生成：

```text
CDC Snapshot Report

2026-07-12
```

例如：

| Batch | Watermark | Result | Time     |
| ----- | --------- | ------ | -------- |
| JOB1  | 1005      | READY  | 13:00:03 |
| JOB2  | 1800      | READY  | 14:10:22 |
| JOB3  | 2500      | FAILED | 15:33:18 |

------

# 如果领导问：

> "昨天为什么 JOB2 FAILED？"

直接：

查：

```sql
SELECT report

FROM snapshot_audit

WHERE checkpoint_id='JOB2-20260712';
```

里面：

完整：

JSON：

```json
{
    ...
    "validation":{

        "lagZero":false,

        "customerLag":324,

        "sequenceCheck":true

    }
}
```

立即：

知道：

为什么。

------

# 所以我不会设计 READY/COMPLETED

而会设计：

```java
enum CheckpointResult {

    READY,

    FAILED,

    TIMEOUT

}
```

为什么？

因为：

**READY**

已经：

意味着：

这次：

Audit：

结束。

以后：

都是：

历史。

------

# StateStore

只有：

```java
enum CheckpointState {

    WAITING
}
```

StateStore：

就是：

```text
还有哪些 Batch 没完成？
```

------

Audit：

就是：

```java
enum AuditResult {

    READY,

    FAILED,

    TIMEOUT
}
```

永久：

保存。

------

# 我会再加一张 Summary 表

例如：

```text
snapshot_summary
```

每天：

一条：

```text
2026-07-12

Batch

Ready

Failed

Timeout
```

例如：

| Date       | Total | Ready | Failed | Timeout |
| ---------- | ----- | ----- | ------ | ------- |
| 2026-07-12 | 15    | 15    | 0      | 0       |

领导：

每天：

看：

这个。

------

# 真正企业里

实际上：

最终：

有三张表。

```text
snapshot_checkpoint
```

运行中：

```text
WAITING
```

------

```text
snapshot_audit
```

每个：

Batch：

一条：

完整：

JSON。

------

```text
snapshot_summary
```

每天：

统计。

------

## 我觉得如果是银行或者物流项目（例如你一直说的 Yamato 这种批处理场景），我还会再加一张：

```text
snapshot_validation_detail
```

不要把所有校验结果都塞在 JSON 里，而是把每一条校验规则拆成明细。例如：

| Checkpoint    | Rule             | Result | Detail                   |
| ------------- | ---------------- | ------ | ------------------------ |
| JOB1-20260712 | MarkerReceived   | PASS   | Marker Seq=1005          |
| JOB1-20260712 | LagZero          | PASS   | All topics lag=0         |
| JOB1-20260712 | JournalSequence  | PASS   | Watermark=1005           |
| JOB1-20260712 | JournalTimestamp | PASS   | All timestamps <= Marker |

这样有两个好处：

1. **日报**可以直接统计："今天有多少 Batch 因为 LagZero 失败？"
2. **审计**时不用解析 JSON，直接 SQL 就能定位失败原因。

这是很多企业审计系统采用的设计：**运行状态（StateStore）→ 审计主表（Audit）→ 审计明细表（Validation Detail）→ 日汇总（Summary）**。这样既满足实时处理，又方便后续报表、统计和审计追溯。