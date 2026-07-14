我觉得这里已经不是一个 Kafka Streams Demo 了，而是在设计一个**CDC Coordinator（CDC 断面协调器）**。

如果让我从零设计，我不会把 **JOB1、ORDER、DETAIL** 写死到代码里，而是**全部配置化**。

------

# 一、整体架构

```text
                    IBM i
                       │
                Journal (ORDJRN)
                       │
                IBM CDC for i
                       │
        ┌──────────────┼──────────────┐
        │              │              │
        ▼              ▼              ▼
   order-topic   detail-topic   customer-topic
                       │
                 marker-topic
                       │
              Kafka Streams
                       │
          ┌────────────┴─────────────┐
          │                          │
     TopicProgressStore         MarkerStore
          │                          │
          └────────────┬─────────────┘
                       ▼
              Snapshot Coordinator
                       │
                snapshot-audit-topic
```

------

# 二、不要把 Job 写死

例如：

```yaml
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

以后：

增加：

```text
JOB_PAYMENT
```

不用改代码。

------

# 三、Topic 配置

```yaml
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

------

# 四、TopicProgress

```java
public class TopicProgress {

    private String topic;

    private String table;

    private String journal;

    private long lastJournalSequence;

    private Instant lastJournalTimestamp;

    private long kafkaOffset;

    private long kafkaPartition;

    private Instant lastSeenTime;

    private long consumerLag;

}
```

StateStore：

```
Key

TopicName

↓

TopicProgress
```

------

# 五、MarkerStore

```
CheckpointId

↓

MarkerInfo
public class MarkerInfo {

    private String checkpointId;

    private String jobId;

    private long watermarkSequence;

    private Instant watermarkTimestamp;

    private Instant receiveTime;

}
```

------

# 六、Job 配置对象

```java
public class JobDefinition {

    private String jobId;

    private List<String> topics;

}
```

例如：

```
JOB_ORDER

↓

order-header-topic

order-detail-topic
```

------

# 七、Snapshot Coordinator

收到 Marker：

```
JOB_ORDER

↓

Watermark=1005
```

读取：

JobDefinition：

```
JOB_ORDER

↓

需要检查：

order-header-topic

order-detail-topic
```

然后：

StateStore：

```
order-header-topic

↓

1004
order-detail-topic

↓

1002
```

最后：

生成：

Audit。

------

# 八、最终 Audit

我建议不要叫 READY。

而是：

```json
{
  "checkpointId": "20260712-00001",

  "jobId": "JOB_ORDER",

  "decision": {

      "snapshotReady": true,

      "decisionTime": "2026-07-12T13:00:03.120"
  },

  "marker": {

      "journal":"ORDJRN",

      "watermarkSequence":1005,

      "watermarkTimestamp":"2026-07-12T13:00:03.000"
  },

  "topics":[

      {

          "topic":"order-header-topic",

          "table":"ORDER_HEADER",

          "lastJournalSequence":1004,

          "lastJournalTimestamp":"2026-07-12T13:00:02.800",

          "consumerLag":0,

          "result":"PASS"

      },

      {

          "topic":"order-detail-topic",

          "table":"ORDER_DETAIL",

          "lastJournalSequence":1002,

          "lastJournalTimestamp":"2026-07-12T13:00:02.600",

          "consumerLag":0,

          "result":"PASS"

      }

  ],

  "validation":{

      "sameJournal":true,

      "lagZero":true,

      "journalSequence":true,

      "journalTimestamp":true
  }

}
```

------

# 九、Kafka Streams Topology

```
Business Topics
        │
        ▼
ProgressProcessor
        │
        ▼
TopicProgressStore
        ▲
        │
Marker Topic
        │
        ▼
MarkerProcessor
        │
        ▼
MarkerStore
        │
        ▼
SnapshotCoordinator
        │
        ▼
snapshot-audit-topic
```

------

# 十、真正的代码分层

我不会在 `MarkerProcessor` 里面写判断逻辑。

而是拆成几个类：

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

这样做有几个好处：

- **新增 Job**：只改 YAML，不改 Java。
- **新增业务表**：只改配置，不改算法。
- **新增校验规则**（例如以后增加 Transaction ID、Commit ID）：只扩展 `ValidationService`。
- **Kafka Streams Processor** 保持很薄，只负责更新状态和转发事件；真正的业务逻辑集中在 `SnapshotCoordinator` 中，便于单元测试和后续维护。

------

## 我还建议再增加一个"规则引擎"配置

不要把判断条件写死，例如：

```yaml
validation:
  requireSameJournal: true
  requireLagZero: true
  requireSequenceCheck: true
  requireTimestampCheck: true
```

以后如果某个项目不需要 Timestamp 校验，或者以后你决定加入 `transactionId`、`commitId` 等新的校验规则，只需要改配置，不需要改核心代码。这会让整个 **CDC Snapshot Coordinator** 更容易适配不同项目。

---

**有影响，而且影响很大。\**不过这个影响不是坏事，而是\**决定了算法应该怎么写**。

实际上，你这里提出的是整个设计里最关键的问题。

------

## 举个例子

假设：

```text
ORDER_HEADER
ORDER_DETAIL
CUSTOMER
```

Batch：

```text
BEGIN

更新100万条 ORDER

更新300万条 DETAIL

更新50万条 CUSTOMER

INSERT Marker

COMMIT
```

Journal：

```text
999998 ORDER

999999 DETAIL

1000000 CUSTOMER

1000001 MARKER
```

CDC：

由于 Topic 不同：

```
ORDER Topic
```

可能：

```text
999998
```

已经：

发送完成。

但是：

```
DETAIL Topic
```

还在：

```text
998500
```

因为：

数据：

太多。

Marker：

只有：

```text
1000001
```

一条。

所以：

**Marker 很可能最先到 Kafka Streams。**

------

## 那是不是算法错了？

**不是。**

真正的问题是：

**不能在收到 Marker 的时候做一次判断，然后结束。**

而应该：

> **Marker 到达以后，进入 Pending 状态。**

------

## 我会这样设计

Marker：

来了：

```
JOB1

Watermark=1000001
```

MarkerStore：

```text
JOB1

↓

Pending
```

不要：

立即：

判断。

------

然后：

每收到：

任何：

业务消息：

例如：

```
DETAIL

998501
```

更新：

TopicProgress。

更新以后：

自动：

检查：

```
MarkerStore
```

里面：

所有：

Pending Marker。

------

例如：

第一次：

```
DETAIL

998800
```

检查：

```
JOB1

×

Not Ready
```

继续。

------

后来：

```
DETAIL

999500
```

再检查。

还是：

```
×

Not Ready
```

------

最后：

```
DETAIL

1000000
```

Lag：

```text
0
```

这时候：

自动：

变成：

```
READY
```

输出：

```
SnapshotReady
```

然后：

删除：

```
JOB1
```

------

## 所以流程应该改成这样

不是：

```
Marker 到

↓

检查

↓

结束
```

而是：

```
Marker 到

↓

Pending Marker

↓

等待业务 CDC 推进

↓

每收到一条业务消息

↓

重新检查

↓

Ready

↓

输出
```

------

# Kafka Streams 非常适合做这个

因为：

每收到：

一条：

业务消息：

例如：

```java
process(record)
```

更新：

StateStore：

以后：

直接：

```java
checkPendingMarker();
```

Marker：

不用：

重新：

收到。

它：

一直：

躺在：

MarkerStore。

------

# 整个状态机应该这样

```text
Marker

↓

RECEIVED

↓

PENDING

↓

CHECKING

↓

READY

↓

COMPLETED
```

例如：

```
JOB1

↓

Pending
```

DETAIL：

不断：

推进。

每推进一次：

```
Pending

↓

Checking
```

如果：

失败：

```
Checking

↓

Pending
```

继续。

成功：

```
Checking

↓

Ready

↓

Completed
```

删除：

Marker。

------

# 我甚至建议 MarkerStore 加状态

例如：

```java
public class MarkerInfo {

    String checkpointId;

    String jobId;

    long watermarkSequence;

    Instant watermarkTimestamp;

    MarkerStatus status;

}
```

状态：

```java
enum MarkerStatus {

    RECEIVED,

    PENDING,

    READY,

    COMPLETED

}
```

------

# 这样整个算法就变成了"事件驱动"

不是：

```
Marker

触发
```

而是：

两个事件：

```
① Business CDC

② Marker CDC
```

任何一个事件：

都：

触发：

```
Coordinator
```

重新：

判断。

这才符合：

Kafka Streams：

Event Driven。

------

## 不过，我还会再改一个地方（这是生产环境推荐的）

我**不会在每收到一条业务消息都遍历所有 Pending Marker**。

原因：

如果：

```
1000 个 Batch

×

500 个 Topic
```

那么：

每条消息：

都：

```
1000 × 500
```

检查。

代价：

太高。

我会：

把 MarkerStore：

按照：

```
WatermarkSequence
```

排序。

例如：

```
1005

↓

1400

↓

1800
```

每次：

只检查：

**最小的那个 Pending Marker**。

因为：

如果：

1005

都：

还没 Ready。

那么：

1400

一定：

也：

不可能 Ready。

这样：

复杂度：

从：

```
O(所有 Marker × 所有 Topic)
```

降低到：

```
O(所有 Topic)
```

对于长期运行的 Kafka Streams 应用，这个优化非常重要，也更符合生产环境的设计。