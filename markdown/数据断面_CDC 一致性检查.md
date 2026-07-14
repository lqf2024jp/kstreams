Batch 数据断面

in:

```
jobs:

  JOB_ORDER:
    markerTopic: marker-topic
    businessTopics:
      - order-header-topic
      - order-detail-topic

  JOB_CUSTOMER:
    markerTopic: marker-topic
    businessTopics:
      - customer-topic
      - customer-address-topic

  JOB_ACCOUNT:
    markerTopic: marker-topic
    businessTopics:
      - account-topic
      - balance-topic
      - transaction-topic
```

```
topics:

  order-header-topic:
      table: ORDER_HEADER
      journal: ORDJRN

  order-detail-topic:
      table: ORDER_DETAIL
      journal: ORDJRN

  customer-topic:
      table: CUSTOMER
      journal: ORDJRN
```



out:

```
{
  "batch": {
    "jobId": "JOB1",
    "status": "FINISH",
    "batchStartTime": "2026-07-12T12:30:00.000",
    "batchFinishTime": "2026-07-12T13:00:03.000"
  },

  "marker": {
    "journalLibrary": "JRNLIB",
    "journalName": "ORDJRN",
    "watermarkSequence": 1005,
    "watermarkTimestamp": "2026-07-12T13:00:03.000",
    "kafkaTopic": "marker-topic",
    "kafkaPartition": 0,
    "kafkaOffset": 2587
  },

  "topics": {
    "ORDER_HEADER": {
      "journalLibrary": "JRNLIB",
      "journalName": "ORDJRN",
      "lastJournalSequence": 1004,
      "lastJournalTimestamp": "2026-07-12T13:00:02.800",
      "lastKafkaOffset": 185432,
      "lastKafkaTimestamp": "2026-07-12T13:00:02.910",
      "lastSeenTime": "2026-07-12T13:00:02.930",
      "consumerLag": 0,
      "ready": true
    },

    "ORDER_DETAIL": {
      "journalLibrary": "JRNLIB",
      "journalName": "ORDJRN",
      "lastJournalSequence": 1002,
      "lastJournalTimestamp": "2026-07-12T13:00:02.600",
      "lastKafkaOffset": 84231,
      "lastKafkaTimestamp": "2026-07-12T13:00:02.720",
      "lastSeenTime": "2026-07-12T13:00:02.740",
      "consumerLag": 0,
      "ready": true
    },

    "CUSTOMER": {
      "journalLibrary": "JRNLIB",
      "journalName": "ORDJRN",
      "lastJournalSequence": 1004,
      "lastJournalTimestamp": "2026-07-12T13:00:02.900",
      "lastKafkaOffset": 96321,
      "lastKafkaTimestamp": "2026-07-12T13:00:02.980",
      "lastSeenTime": "2026-07-12T13:00:03.010",
      "consumerLag": 0,
      "ready": true
    }

  },

  "validation": {
    "markerReceived": true,
    "allTopicsLagZero": true,
    "journalSequenceCheck": true,
    "journalTimestampCheck": true,
    "sameJournal": true
  },

  "snapshot": {
    "snapshotReady": true,
    "decisionTime": "2026-07-12T13:00:03.020",
    "reason": "All topics reached watermark boundary."
  }
}
```

**非常适合，而且这类问题本来就是 Kafka Streams 擅长的。**不过，我建议稍微调整一下你的设计思路。

先说结论：

> **Kafka Streams 可以很容易实现这种"Barrier/Watermark 检查"，但真正作为断面判断依据应该是 Journal Sequence；Journal Timestamp 更适合作为校验和监控，而不是主要判断条件。**

------

```
cdc-checker
│
├── config
│     ├── JobDefinition.java
│     ├── TopicDefinition.java
│     └── CheckerProperties.java
│
├── model
│     ├── TopicProgress.java
│     ├── MarkerInfo.java
│     ├── SnapshotAudit.java
│     └── ValidationResult.java
│
├── processor
│     ├── ProgressProcessor.java
│     ├── MarkerProcessor.java
│     └── AuditProcessor.java
│
├── service
│     ├── TopicProgressService.java
│     ├── MarkerService.java
│     ├── SnapshotCoordinator.java
│     └── ValidationService.java
│
├── store
│     ├── TopicProgressStore.java
│     └── MarkerStore.java
│
└── topology
      └── CheckerTopology.java
```



# 你的数据流

假设有四个 Topic：

```text
order-topic
detail-topic
customer-topic
marker-topic
```

消息都带有：

```json
"source": {
    "journal_name":"ORDJRN",
    "sequence_number":1003,
    "timestamp":"2026-07-12T13:00:02.123456"
}
```

Marker：

```json
{
    "batch":"JOB1",
    "source":{
        "sequence_number":1005,
        "timestamp":"2026-07-12T13:00:03.000000"
    }
}
```

------

# Kafka Streams 怎么做？

## 第一件事

每收到一条业务消息：

维护：

```text
Topic State

ORDER
Last Sequence:1003
Last Timestamp:13:00:02.123
```

DETAIL：

```text
1002
```

CUSTOMER：

```text
1004
```

这些状态放到：

```
StateStore(RocksDB)
```

例如：

```
TopicStatusStore

Key:ORDER

Value{
    lastSeq:1003,
    lastTimestamp:...
}
```

Kafka Streams 做这个几乎就是几行代码。

------

## 第二件事

收到 Marker：

```text
Marker

Watermark:1005
```

Streams：

开始检查：

StateStore：

```
ORDER:1003

DETAIL:1002
CUSTOMER:1004
```

如果：

```
全部

<1005
```

说明：

目前：

业务消息：

已经追到 Marker。

------

## 第三件事

再检查 Timestamp

例如：

Marker：

```
13:00:03.000
```

ORDER：

```
13:00:02.800
```

DETAIL：

```
13:00:02.600
```

CUSTOMER：

```
13:00:02.900
```

都：

<= Marker

就：

通过。

------

# Kafka Streams 好不好写？

实际上非常好写。

例如：

业务流：

```java
builder.stream("order-topic")
       .process(new UpdateStateStoreProcessor());
```

Marker：

```java
builder.stream("marker-topic")
       .process(new MarkerCheckProcessor());
```

MarkerCheckProcessor：

里面：

```java
stateStore.get("ORDER");

stateStore.get("DETAIL");

stateStore.get("CUSTOMER");
```

比较：

```
LastSeq

LastTimestamp
```

然后：

输出：

```text
JOB1 CLEAN
```

或者：

```text
JOB1 NOT CLEAN
```

------

# 但是……

我建议你不要检查：

```
Topic Last Sequence
```

而应该检查：

**Consumer 已经处理到哪里。**

为什么？

例如：

ORDER：

Journal：

```
1001

1005

1010
```

DETAIL：

```
1002

1004
```

ORDER：

LastSeq：

```
1010
```

其实：

不能说明：

```
1005
```

之前：

全部：

Apply。

如果：

你的程序：

还有：

内部 Queue。

就：

不成立。

------

# 我会这样设计

StateStore：

```
TopicStatus
```

里面：

```
LastConsumedSequence

LastAppliedSequence

LastTimestamp

Lag

QueueSize
```

Marker：

```
WatermarkSequence

WatermarkTimestamp
```

收到 Marker：

判断：

```
LastAppliedSequence >= WatermarkSequence?
```

以及：

```
Lag==0
```

以及：

```
QueueSize==0
```

然后：

输出：

```
Snapshot Ready
```

------

# 如果让我设计

我甚至不会让 Marker Processor 自己去轮询。

而是：

Streams：

维护：

一个：

```
GlobalKTable
```

里面：

一直保存：

```
ORDER

↓

State
DETAIL

↓

State
CUSTOMER

↓

State
```

Marker：

一来：

立即：

Join：

State。

然后：

判断：

```
Ready?
```

Kafka Streams：

原生支持。

代码：

其实：

100 行左右。

------

# 我认为你的这个需求，其实就是一个"Barrier Detection"问题

如果用 Kafka Streams，我会把它设计成下面这个拓扑：

```text
                    ORDER Topic
                         │
                         ▼
                 UpdateStateProcessor
                         │
                    StateStore
                         ▲
                         │
DETAIL Topic ────────────┤
                         │
CUSTOMER Topic ──────────┘

                    MARKER Topic
                         │
                         ▼
                BarrierCheckProcessor
                         │
          读取 StateStore（Sequence、Timestamp）
                         │
        判断：
        - Marker 是否已到达
        - Sequence 是否达到 Watermark
        - Timestamp 是否异常
                         │
                         ▼
          snapshot-ready-topic
```

这是一个非常典型的 Kafka Streams 有状态处理（Stateful Processing）场景。

------

### 我还有一个建议

**如果你真的准备把这个做成生产系统，我建议不要只做一个 `snapshot-ready-topic`。**

再输出一个：

```text
snapshot-audit-topic
```

每次判断时，把所有状态都记录下来，例如：

```json
{
  "batch": "JOB1",
  "watermarkSequence": 1005,
  "watermarkTimestamp": "2026-07-12T13:00:03.000",
  "topics": {
    "ORDER": {
      "lastAppliedSequence": 1004,
      "lastTimestamp": "2026-07-12T13:00:02.800"
    },
    "DETAIL": {
      "lastAppliedSequence": 1002,
      "lastTimestamp": "2026-07-12T13:00:02.600"
    },
    "CUSTOMER": {
      "lastAppliedSequence": 1004,
      "lastTimestamp": "2026-07-12T13:00:02.900"
    }
  },
  "result": "READY"
}
```

这样以后如果有人问："为什么这个 Batch 被判定为可以切断面？" 你可以直接拿出这条审计记录。这在金融、物流等需要可追溯性的系统中非常有价值。

----

我赞成，而且**如果你的目标是做 CDC 审计（Audit）和数据断面判断，那么名字应该尽量贴近业务含义，而不是 Kafka Streams 内部实现。**

我建议不要叫：

```text
lastAppliedSequence
```

因为：

- Applied 到哪里？（Kafka？PostgreSQL？内存？）
- "Applied" 含义比较模糊。

对于 CDC 来说，更准确的是：

```text
Last Journal Sequence
```

或者更完整一点：

```text
Last Processed Journal Sequence
```

表示：

> **该 Topic 已经成功处理（并完成业务逻辑）的最后一个 Journal Sequence。**

------

## 我建议记录下面几个字段

例如：

```json
{
  "topic": "ORDER_HEADER",

  "lastJournalSequence": 123456789,

  "lastJournalTimestamp": "2026-07-12T13:58:10.123456",

  "lastConsumedTime": "2026-07-12T13:58:11.021",

  "lastProcessedTime": "2026-07-12T13:58:11.053",

  "consumerLag": 0
}
```

这里每个时间代表不同意义：

| 字段                 | 来源          | 作用                                           |
| -------------------- | ------------- | ---------------------------------------------- |
| lastJournalSequence  | IBM i Journal | 一致性判断（最重要）                           |
| lastJournalTimestamp | IBM i Journal | 判断业务发生时间、延迟分析                     |
| lastConsumedTime     | Kafka Streams | 什么时候消费到这条消息                         |
| lastProcessedTime    | Kafka Streams | 什么时候真正处理完成（例如写 PostgreSQL 完成） |
| consumerLag          | Kafka         | 是否还有未消费消息                             |

------

## 为什么要有 ProcessedTime？

举个例子：

```
13:00:01

Kafka 收到 Message
```

↓

```
13:00:01.100

Kafka Streams poll()
```

↓

```
13:00:03.500

PostgreSQL Commit
```

如果：

```text
Marker

13:00:02
```

到了。

你看到：

```text
Last Journal Sequence=1004
```

但是：

```text
ProcessedTime

13:00:05
```

说明：

虽然 Sequence 已经到了，

真正：

```text
PostgreSQL
```

可能：

还没写完。

所以：

如果你的 Snapshot 是：

```text
PostgreSQL
```

那么：

真正应该比较的是：

> **Last Processed Journal Sequence**

而不是：

> Consumer Poll 到哪里。

------

## 我会设计一张 State 表

例如：

| Topic    | Last Journal Sequence | Last Journal Timestamp | Last Processed Time | Lag  |
| -------- | --------------------- | ---------------------- | ------------------- | ---- |
| ORDER    | 1004                  | 13:00:02.800           | 13:00:03.120        | 0    |
| DETAIL   | 1002                  | 13:00:02.600           | 13:00:03.101        | 0    |
| CUSTOMER | 1003                  | 13:00:02.700           | 13:00:03.110        | 0    |

Marker：

```
Watermark Sequence

1005
```

然后：

Kafka Streams：

判断：

```text
所有 Topic：

Last Journal Sequence < Watermark Sequence
```

并且：

```text
Lag==0
```

然后：

```text
Snapshot Ready
```

------

## 我还有一个建议（生产系统很有用）

既然你已经记录：

```text
Last Journal Timestamp
```

再计算一个：

```text
CDC Delay

=

Last Processed Time

-

Last Journal Timestamp
```

例如：

| Topic    | Delay |
| -------- | ----- |
| ORDER    | 520ms |
| DETAIL   | 480ms |
| CUSTOMER | 610ms |

这样你可以实时监控：

- CDC 是否变慢？
- Kafka 是否积压？
- PostgreSQL 是否写入变慢？

很多企业都会把这个指标接到监控系统（如 Prometheus + Grafana）里。

------

**我很喜欢你现在的思路。**你其实不是在做一个普通的 Kafka Streams 程序，而是在设计一个 **CDC Consistency Checker（CDC 一致性检查器）**。对于这种系统，字段命名越贴近 IBM i Journal（`Journal Sequence`、`Journal Timestamp`）越好，因为将来排查问题时可以直接和 IBM i 的 Journal 信息对应，不需要再去解释 `AppliedSequence` 到底是什么意思。

---

我赞成，而且**如果你的目标是做 CDC 审计（Audit）和数据断面判断，那么名字应该尽量贴近业务含义，而不是 Kafka Streams 内部实现。**

我建议不要叫：

```text
lastAppliedSequence
```

因为：

- Applied 到哪里？（Kafka？PostgreSQL？内存？）
- "Applied" 含义比较模糊。

对于 CDC 来说，更准确的是：

```text
Last Journal Sequence
```

或者更完整一点：

```text
Last Processed Journal Sequence
```

表示：

> **该 Topic 已经成功处理（并完成业务逻辑）的最后一个 Journal Sequence。**

------

## 我建议记录下面几个字段

例如：

```json
{
  "topic": "ORDER_HEADER",

  "lastJournalSequence": 123456789,

  "lastJournalTimestamp": "2026-07-12T13:58:10.123456",

  "lastConsumedTime": "2026-07-12T13:58:11.021",

  "lastProcessedTime": "2026-07-12T13:58:11.053",

  "consumerLag": 0
}
```

这里每个时间代表不同意义：

| 字段                 | 来源          | 作用                                           |
| -------------------- | ------------- | ---------------------------------------------- |
| lastJournalSequence  | IBM i Journal | 一致性判断（最重要）                           |
| lastJournalTimestamp | IBM i Journal | 判断业务发生时间、延迟分析                     |
| lastConsumedTime     | Kafka Streams | 什么时候消费到这条消息                         |
| lastProcessedTime    | Kafka Streams | 什么时候真正处理完成（例如写 PostgreSQL 完成） |
| consumerLag          | Kafka         | 是否还有未消费消息                             |

------

## 为什么要有 ProcessedTime？

举个例子：

```
13:00:01

Kafka 收到 Message
```

↓

```
13:00:01.100

Kafka Streams poll()
```

↓

```
13:00:03.500

PostgreSQL Commit
```

如果：

```text
Marker

13:00:02
```

到了。

你看到：

```text
Last Journal Sequence=1004
```

但是：

```text
ProcessedTime

13:00:05
```

说明：

虽然 Sequence 已经到了，

真正：

```text
PostgreSQL
```

可能：

还没写完。

所以：

如果你的 Snapshot 是：

```text
PostgreSQL
```

那么：

真正应该比较的是：

> **Last Processed Journal Sequence**

而不是：

> Consumer Poll 到哪里。

------

## 我会设计一张 State 表

例如：

| Topic    | Last Journal Sequence | Last Journal Timestamp | Last Processed Time | Lag  |
| -------- | --------------------- | ---------------------- | ------------------- | ---- |
| ORDER    | 1004                  | 13:00:02.800           | 13:00:03.120        | 0    |
| DETAIL   | 1002                  | 13:00:02.600           | 13:00:03.101        | 0    |
| CUSTOMER | 1003                  | 13:00:02.700           | 13:00:03.110        | 0    |

Marker：

```
Watermark Sequence

1005
```

然后：

Kafka Streams：

判断：

```text
所有 Topic：

Last Journal Sequence

<

Watermark Sequence
```

并且：

```text
Lag==0
```

然后：

```text
Snapshot Ready
```

------

## 我还有一个建议（生产系统很有用）

既然你已经记录：

```text
Last Journal Timestamp
```

再计算一个：

```text
CDC Delay

=

Last Processed Time

-

Last Journal Timestamp
```

例如：

| Topic    | Delay |
| -------- | ----- |
| ORDER    | 520ms |
| DETAIL   | 480ms |
| CUSTOMER | 610ms |

这样你可以实时监控：

- CDC 是否变慢？
- Kafka 是否积压？
- PostgreSQL 是否写入变慢？

很多企业都会把这个指标接到监控系统（如 Prometheus + Grafana）里。

------

**我很喜欢你现在的思路。**你其实不是在做一个普通的 Kafka Streams 程序，而是在设计一个 **CDC Consistency Checker（CDC 一致性检查器）**。对于这种系统，字段命名越贴近 IBM i Journal（`Journal Sequence`、`Journal Timestamp`）越好，因为将来排查问题时可以直接和 IBM i 的 Journal 信息对应，不需要再去解释 `AppliedSequence` 到底是什么意思。

----

我觉得你这个方案已经可以称为一个完整的**CDC Checkpoint / Barrier（断面判断）方案**了。我先总结设计，再给出 Kafka Streams 的实现思路和代码骨架。

------

# 一、架构

```text
        AS400 (IBM i)

        ORDER_HEADER
        ORDER_DETAIL
        CUSTOMER
        CDC_MARKER
              │
              │ 同一个 Journal (ORDJRN)
              ▼
        IBM CDC for i
              │
              ▼
            Kafka
    ┌─────────┼──────────┐
    │         │          │
 ORDER     DETAIL    CUSTOMER
 Topic      Topic      Topic
    │         │          │
    └─────────┼──────────┘
              │
              ▼
      Kafka Streams
              │
      StateStore(RocksDB)
              │
              ▼
 Snapshot Ready Topic
```

------

# 二、Marker

Batch 最后：

```sql
BEGIN

UPDATE ORDER_HEADER...

UPDATE ORDER_DETAIL...

UPDATE CUSTOMER...

INSERT INTO CDC_MARKER
(
    BATCH_ID,
    STATUS
)
VALUES
(
    'JOB1',
    'END'
);

COMMIT;
```

因为：

CDC_MARKER

和业务表

同一个 Journal。

所以：

Journal：

```text
Seq

1001 ORDER

1002 DETAIL

1003 CUSTOMER

1004 ORDER

1005 MARKER

1006 COMMIT
```

那么：

```text
Watermark Sequence =1005
```

就是：

整个 Batch 的边界。

------

# 三、Kafka Message

例如：

ORDER

```json
{
  "after": {
    "ORDER_ID": 10001
  },
  "source": {
    "journal":"ORDJRN",
    "sequence":1004,
    "timestamp":"2026-07-12T13:00:02.500"
  }
}
```

Marker

```json
{
  "batch":"JOB1",
  "source":{

      "journal":"ORDJRN",

      "sequence":1005,

      "timestamp":"2026-07-12T13:00:03.000"

  }
}
```

------

# 四、Kafka Streams 保存什么？

我建议：

StateStore：

```text
TopicProgress
```

Value：

```java
class TopicProgress {

    String topic;

    long lastJournalSequence;

    Instant lastJournalTimestamp;

    Instant lastSeenTime;

}
```

这里：

lastSeenTime：

就是：

```java
Instant.now();
```

收到消息的时候。

------

# 五、每收到业务消息

例如：

ORDER：

```text
Sequence

1004
```

更新：

```text
ORDER

↓

LastJournalSequence=1004

LastJournalTimestamp=13:00:02.500

LastSeenTime=13:00:03.100
```

DETAIL：

同样。

------

# 六、收到 Marker

例如：

```text
Watermark

1005
```

Streams：

读取：

StateStore：

```text
ORDER

1004
```

DETAIL：

```text
1002
```

CUSTOMER：

```text
1003
```

再检查：

Kafka：

```text
Lag==0
```

如果：

全部：

成立。

输出：

```json
{
    "batch":"JOB1",

    "watermark":1005,

    "status":"READY"
}
```

------

# 七、为什么不用 Timestamp 判断？

因为：

Journal：

```text
Sequence

1001

↓

1002

↓

1003

↓

1004

↓

1005
```

已经：

严格：

单调递增。

Timestamp：

只是：

辅助。

用于：

```text
CDC Delay

=

SeenTime

-

JournalTimestamp
```

监控。

不是：

一致性。

------

# 八、Kafka Streams 实现

先定义：

```java
public class TopicProgress {

    private String topic;

    private long lastJournalSequence;

    private Instant lastJournalTimestamp;

    private Instant lastSeenTime;

}
```

------

Processor：

```java
public class ProgressProcessor
        extends ContextualProcessor<String, CdcMessage, Void, Void> {

    private KeyValueStore<String, TopicProgress> store;

    @Override
    public void init(ProcessorContext<Void, Void> context) {

        super.init(context);

        store = context.getStateStore("topic-progress");
    }

    @Override
    public void process(Record<String, CdcMessage> record) {

        TopicProgress progress =
                new TopicProgress();

        progress.setTopic(record.topic());

        progress.setLastJournalSequence(
                record.value()
                      .getSource()
                      .getSequence());

        progress.setLastJournalTimestamp(
                record.value()
                      .getSource()
                      .getTimestamp());

        progress.setLastSeenTime(
                Instant.now());

        store.put(record.topic(), progress);

    }

}
```

------

Marker Processor

```java
public class MarkerProcessor
        extends ContextualProcessor<String, MarkerMessage, Void, SnapshotReady> {

    private KeyValueStore<String, TopicProgress> store;

    @Override
    public void process(Record<String, MarkerMessage> record) {

        long watermark =
                record.value()
                      .getSource()
                      .getSequence();

        boolean ready = true;

        TopicProgress order =
                store.get("order-topic");

        TopicProgress detail =
                store.get("detail-topic");

        TopicProgress customer =
                store.get("customer-topic");

        if (order.getLastJournalSequence() >= watermark)
            ready = false;

        if (detail.getLastJournalSequence() >= watermark)
            ready = false;

        if (customer.getLastJournalSequence() >= watermark)
            ready = false;

        if (ready) {

            context().forward(
                    new Record<>(
                            "JOB1",
                            new SnapshotReady("JOB1", watermark),
                            record.timestamp()
                    ));

        }

    }

}
```

------

Topology：

```java
StreamsBuilder builder = new StreamsBuilder();

builder.stream("order-topic")
       .process(ProgressProcessor::new);

builder.stream("detail-topic")
       .process(ProgressProcessor::new);

builder.stream("customer-topic")
       .process(ProgressProcessor::new);

builder.stream("marker-topic")
       .process(MarkerProcessor::new);
```

------

# 九、我建议再改进一点（真正生产环境）

上面的代码只是演示思路，但真正生产环境我会再改两点：

1. **不要让 `MarkerProcessor` 自己去读取三个固定 Topic 的状态。**
   应该维护一张 `StateStore`：

   ```text
   Topic
       ↓
   LastJournalSequence
   ```

   `MarkerProcessor` 遍历 Store 即可，这样以后增加业务表，不需要改代码。

2. **不要直接检查 Kafka Lag。**
   Kafka Streams API 本身并不直接提供 Consumer Lag。更好的做法是：

   - 由外部监控（如 Consumer Group Lag）确认 Lag 为 0；或者
   - 让 Snapshot 管理程序收到 `SnapshotReady` 后，再调用 Kafka Admin API 验证 Consumer Group Lag。

------

## 最后提醒一个非常关键的问题

你前面的思路里有一句：

> **各个业务 Topic 的 `LastJournalSequence < WatermarkSequence` 就表示断面干净。**

这里需要修正一下。

例如：

```
Journal

1001 ORDER
1002 DETAIL
1003 ORDER
1004 CUSTOMER
1005 MARKER
```

`order-topic` 的最大 Sequence 永远是 **1003**，因为 **1004 属于 CUSTOMER**。

所以**不能要求每个 Topic 都追到 1005**，而是应该要求：

- 每个业务 Topic 已经**消费到自己的末尾**（没有积压）。
- Marker 已经收到。
- Marker 所在 Journal 的 `WatermarkSequence` 定义了这一批的边界。

也就是说，**Watermark 是一个全局边界，而不是每个 Topic 必须达到的目标 Sequence**。这一点对算法的正确性非常重要。

---



我建议把它设计成**审计结果（Audit Result）**，而不是简单的 READY。因为以后出了问题，这条 JSON 就是你的"证据链"。

另外，把 `lastAppliedSequence` 改成 **lastJournalSequence** 更符合 IBM i Journal 的概念。

我建议最终结构如下：

```json
{
  "batch": {
    "jobId": "JOB1",
    "status": "FINISH",
    "batchStartTime": "2026-07-12T12:30:00.000",
    "batchFinishTime": "2026-07-12T13:00:03.000"
  },

  "marker": {
    "journalLibrary": "JRNLIB",
    "journalName": "ORDJRN",
    "watermarkSequence": 1005,
    "watermarkTimestamp": "2026-07-12T13:00:03.000",
    "kafkaTopic": "marker-topic",
    "kafkaPartition": 0,
    "kafkaOffset": 2587
  },

  "topics": {

    "ORDER_HEADER": {

      "journalLibrary": "JRNLIB",
      "journalName": "ORDJRN",

      "lastJournalSequence": 1004,
      "lastJournalTimestamp": "2026-07-12T13:00:02.800",

      "lastKafkaOffset": 185432,

      "lastKafkaTimestamp": "2026-07-12T13:00:02.910",

      "lastSeenTime": "2026-07-12T13:00:02.930",

      "consumerLag": 0,

      "ready": true
    },

    "ORDER_DETAIL": {

      "journalLibrary": "JRNLIB",
      "journalName": "ORDJRN",

      "lastJournalSequence": 1002,
      "lastJournalTimestamp": "2026-07-12T13:00:02.600",

      "lastKafkaOffset": 84231,

      "lastKafkaTimestamp": "2026-07-12T13:00:02.720",

      "lastSeenTime": "2026-07-12T13:00:02.740",

      "consumerLag": 0,

      "ready": true
    },

    "CUSTOMER": {

      "journalLibrary": "JRNLIB",
      "journalName": "ORDJRN",

      "lastJournalSequence": 1004,
      "lastJournalTimestamp": "2026-07-12T13:00:02.900",

      "lastKafkaOffset": 96321,

      "lastKafkaTimestamp": "2026-07-12T13:00:02.980",

      "lastSeenTime": "2026-07-12T13:00:03.010",

      "consumerLag": 0,

      "ready": true
    }

  },

  "validation": {

    "markerReceived": true,

    "allTopicsLagZero": true,

    "journalSequenceCheck": true,

    "journalTimestampCheck": true,

    "sameJournal": true
  },

  "snapshot": {

    "snapshotReady": true,

    "decisionTime": "2026-07-12T13:00:03.020",

    "reason": "All topics reached watermark boundary."
  }
}
```

------

## 不过，我建议再修改一个地方

你原来写的是：

```json
"lastJournalSequence":1004
```

其实**还缺少一个非常重要的信息**：

**这条 Sequence 是哪一条消息？**

因为以后排查问题的时候，你需要能够直接定位 Kafka Message。

所以建议增加：

```json
"lastMessage": {
    "journalSequence":1004,
    "journalTimestamp":"2026-07-12T13:00:02.800",

    "kafkaTopic":"order-topic",
    "partition":1,
    "offset":185432,

    "key":"10001"
}
```

这样以后出了问题：

例如：

```text
为什么 JOB1 判定 READY？
```

直接：

```text
ORDER_HEADER

↓

Partition 1

↓

Offset 185432
```

就能把那条 Kafka Message 找出来。

------

## 我还建议增加一个字段（这是银行项目经常有的）

```json
"delay": {
    "cdcDelayMs":110,
    "consumerDelayMs":20
}
```

其中：

```text
cdcDelay

=

Kafka Timestamp

-

Journal Timestamp
consumerDelay

=

SeenTime

-

Kafka Timestamp
```

以后：

Grafana

直接：

画图。

CDC 有没有慢。

一眼就知道。

------

## 如果这是我负责设计，我还会增加最后一个字段

```json
"audit": {
    "algorithmVersion": "1.0.0",
    "checker": "KafkaStreams",
    "hostname": "cdc-checker-01",
    "applicationId": "cdc-snapshot-checker"
}
```

这样：

几年以后，

有人问：

> **"2026 年 7 月 12 日 JOB1 为什么被判定 READY？"**

你不仅能拿出这条 JSON，还能知道：

- 用的是哪个版本的算法。
- 哪台 Kafka Streams 实例做的判断。
- 属于哪个 Consumer Group。

这对于生产系统的可追溯性非常有帮助。

------

### 最后，我想对整个算法再提一个建议

你现在的 `validation` 可以做成**显式规则**，而不是一个简单的 `READY`。例如：

| 检查项                                                       | 判断 |
| ------------------------------------------------------------ | ---- |
| Marker 已收到                                                | ✅    |
| Marker 与业务 Topic 属于同一个 Journal                       | ✅    |
| 所有 Topic Consumer Lag = 0                                  | ✅    |
| 所有 Topic 最后一条消息的 `journalSequence < watermarkSequence` | ✅    |
| 所有 Topic 最后一条消息的 `journalTimestamp <= watermarkTimestamp` | ✅    |

只有**全部通过**，最终才输出：

```json
"snapshotReady": true
```

这样，这份 JSON 不只是结果，更是一份完整的**断面一致性审计报告（Consistency Audit Report）**。这比简单输出 `"READY"` 更适合真正的生产环境。

---

这个问题问得非常好，而且**这正是整个方案真正需要解决的问题。**

如果只有一个 Batch：

```text
JOB1
```

事情很简单。

但是生产环境通常是：

```text
JOB1（每天订单）

JOB2（库存）

JOB3（会员）

JOB4（会计）

……
```

甚至：

```text
JOB1
还没结束

↓

JOB2

已经开始
```

所以设计必须支持**多个 Batch 并发存在**。

------

# 我的建议：Marker 必须是"事件"而不是"状态"

例如 Marker Topic：

```text
Marker Topic

------------------------------------------------

JOB1
Watermark=1005

------------------------------------------------

JOB2
Watermark=1240

------------------------------------------------

JOB3
Watermark=1568

------------------------------------------------
```

Kafka Streams：

不是保存：

```text
Current Marker
```

而是：

维护：

```text
Pending Marker
```

例如：

```text
PendingMarkerStore

JOB1

↓

1005

JOB2

↓

1240

JOB3

↓

1568
```

StateStore：

```
Key

JOB1

Value

MarkerInfo
```

------

# 然后业务 Topic 一直推进

例如：

ORDER：

```text
1001

1002

1008

1200

1300
```

DETAIL：

```text
1003

1005

1230

1250
```

每来一条消息：

更新：

```text
TopicProgress
```

------

# 每更新一次

Kafka Streams：

检查：

所有：

```text
Pending Marker
```

例如：

```
JOB1

1005
```

判断：

```
READY ?
```

如果：

READY：

输出：

```
Snapshot Ready

JOB1
```

然后：

删除：

```
JOB1
```

继续：

```
JOB2
```

------

# 举个例子

Marker：

```
JOB1

1005
```

后来：

```
JOB2

1400
```

Topic：

现在：

```
ORDER

1300
```

DETAIL：

```
1200
```

那么：

```
JOB1

READY
```

但是：

```
JOB2

NOT READY
```

因为：

DETAIL：

还没有：

1400

附近的数据。

------

# 我建议维护两个 Store

## TopicProgress

```
ORDER

↓

1300
DETAIL

↓

1200
CUSTOMER

↓

1350
```

------

## MarkerStore

```
JOB1

↓

1005
JOB2

↓

1400
JOB3

↓

1800
```

------

# Kafka Streams 每收到业务消息

就：

```java
更新：

TopicProgress
```

然后：

遍历：

```
MarkerStore
```

例如：

```
1005
```

如果：

已经：

READY

立即：

Forward：

```
SnapshotReady(JOB1)
```

并且：

```java
markerStore.delete("JOB1");
```

------

# 这样有什么好处？

例如：

一天：

```
JOB1

09:00
JOB2

10:00
JOB3

11:00
```

全部：

存在：

MarkerStore。

Streams：

一直：

自动：

检查。

哪个：

满足。

哪个：

删除。

------

# 更进一步（推荐）

Marker：

最好：

不是：

```
JOB1
```

而是：

```
Checkpoint
```

例如：

```json
{
  "checkpointId":"20260712-000001",

  "batch":"JOB1",

  "watermarkSequence":1005
}
```

因为：

以后：

JOB1：

一天：

跑：

很多次。

例如：

```
JOB1

上午
JOB1

下午
JOB1

晚上
```

Batch 名称：

重复。

但是：

Checkpoint：

不会。

------

# 我建议最终的数据结构

MarkerStore：

```text
CheckpointId

↓

BatchName

↓

WatermarkSequence

↓

WatermarkTimestamp

↓

Status

(PENDING)

↓

CreateTime
```

例如：

| Checkpoint   | Batch | Watermark |
| ------------ | ----- | --------- |
| 20260712-001 | JOB1  | 1005      |
| 20260712-002 | JOB2  | 1400      |
| 20260712-003 | JOB1  | 2100      |

这样：

同一个：

JOB1

一天：

跑：

100 次。

都没问题。

------

## 还有一个需要考虑的情况：**批处理重叠（Overlap）**

例如：

```text
09:00  JOB1 开始
09:10  JOB2 开始
09:20  JOB1 结束（Marker=1005）
09:25  JOB2 结束（Marker=1030）
```

由于 Marker 都在**同一个 Journal**中，它们的 Watermark Sequence 会天然形成顺序：

```text
1005 (JOB1)
1030 (JOB2)
```

Kafka Streams 不需要关心它们是不是重叠执行，只需要：

- 把每个 Marker 当作一个独立的 Checkpoint 保存。
- 按 `watermarkSequence` 从小到大检查。
- 满足条件就输出对应的 Snapshot Ready。

因此，**真正的唯一标识建议使用 `checkpointId`，`batchName` 只是业务名称**。这样既支持多个不同 Batch，也支持同一个 Batch 多次运行，是生产环境中更稳健的设计。