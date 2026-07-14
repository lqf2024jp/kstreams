好，我们继续。

到目前为止，我们已经有了：

```text
Business CDC
      │
      ▼
ProgressProcessor
      │
      ▼
TopicProgressStore
```

现在开始写 **MarkerProcessor**。

------

# 它的职责是什么？

**一句话：**

> 收到 Marker，不立即判断 READY，而是先保存到 `MarkerStore`，等待业务 CDC 慢慢追上。

这是整个算法最重要的思想。

------

# 1. Marker Message

假设 Marker Topic 中收到：

```json
{
  "checkpointId": "20260712-0001",
  "jobId": "JOB_ORDER",

  "source": {
    "journalLibrary": "JRNLIB",
    "journalName": "ORDJRN",

    "journalSequence": 1005,
    "journalTimestamp": "2026-07-12T13:00:03"
  }
}
```

Java：

```java
public class MarkerMessage {

    private String checkpointId;

    private String jobId;

    private Source source;

    // getter setter
}
```

------

# 2. MarkerInfo（StateStore保存对象）

真正放进 StateStore 的不是 MarkerMessage。

而是：

```java
public class MarkerInfo {

    private String checkpointId;

    private String jobId;

    private long watermarkSequence;

    private Instant watermarkTimestamp;

    private Instant receiveTime;

    private MarkerStatus status;

}
```

状态：

```java
public enum MarkerStatus {

    WAITING

}
```

为什么只有 WAITING？

因为：READY不是状态。

READY是：**Coordinator计算出来的结果。**

------

# 3. Marker Store

另外一张 RocksDB

```
marker-store
```

内容：

```
checkpointId
↓

MarkerInfo
```

例如：

```
20260712-0001

↓

JOB_ORDER

↓

1005

↓

WAITING
```

------

# 4. MarkerProcessor

```java
public class MarkerProcessor
extends ContextualProcessor<String,
                            MarkerMessage,
                            String,
                            MarkerMessage> {

    private KeyValueStore<String, MarkerInfo> markerStore;

    @Override
    public void init(
        ProcessorContext<String, MarkerMessage> context) {

        super.init(context);

        markerStore =
            context.getStateStore("marker-store");
    }

    @Override
    public void process(
        Record<String, MarkerMessage> record) {

        MarkerMessage msg = record.value();

        MarkerInfo info = new MarkerInfo();

        info.setCheckpointId(msg.getCheckpointId());

        info.setJobId(msg.getJobId());

        info.setWatermarkSequence(
                msg.getSource()
                   .getJournalSequence());

        info.setWatermarkTimestamp(
                msg.getSource()
                   .getJournalTimestamp());

        info.setReceiveTime(
                Instant.now());

        info.setStatus(
                MarkerStatus.WAITING);

        markerStore.put(
                info.getCheckpointId(),
                info);

        System.out.println(
                "Receive Marker : "
                + info.getCheckpointId());

    }

}
```

这里：

真正重要的只有：

```java
markerStore.put(...)
```

它表示：

```
以后

Coordinator

可以来检查
```

------

# 5. 收到 Marker 后

Store：

变成：

```
MarkerStore

--------------------------------

Checkpoint

20260712-0001

↓

JOB_ORDER

↓

1005

↓

WAITING
```

注意：

**什么都没判断。**

------

# 为什么？

因为：

Marker：

经常：

最先：

到。

例如：

```
Marker

1005
```

但是：

DETAIL：

还：

只有：

```
998
```

如果：

立即：

判断。

一定：

失败。

所以：

保存：

等待。

------

# 6. Topology

现在：

Topology：

已经：

变成：

```
                  order-topic
                       │
                       ▼
               ProgressProcessor
                       │
                       ▼
               TopicProgressStore
                       ▲
                       │
                 detail-topic


marker-topic
      │
      ▼
MarkerProcessor
      │
      ▼
MarkerStore
```

目前：

两张：

StateStore。

------

# 7. 什么时候检查？

这里就是：

很多人第一次学 Streams 会写错的地方。

很多人：

写：

```text
收到 Marker

↓

检查
```

这是错的。

应该：

```
收到 Marker

↓

保存 WAITING

↓

结束
```

以后：

任何：

业务 CDC：

来了：

```
ORDER

↓

1006
```

ProgressProcessor：

更新：

```
TopicProgressStore
```

然后：

通知：

Coordinator。

------

# 8. 所以 ProgressProcessor 要改

以前：

最后：

只有：

```java
store.put(topic,progress);
```

现在：

应该：

变成：

```java
store.put(topic,progress);

coordinator.checkWaitingMarkers();
```

真正：

READY

是在：

这里：

发生。

不是：

MarkerProcessor。

------

# 所以整个流程

```
Marker
    │
    ▼
MarkerProcessor
    │
保存 MarkerStore
    │
    ▼
WAITING
```

以后：

```
Business CDC
      │
      ▼
ProgressProcessor
      │
更新 TopicProgress
      │
      ▼
Coordinator.check()
      │
      ▼
Marker Ready ?
```

所以：

**MarkerProcessor 非常简单。**

它：

**永远不负责 READY。**

------

# 下一步就是整个系统最核心的一部分

下一步我们写 **③ SnapshotCoordinator**。

它会：

1. 读取 `MarkerStore`
2. 读取 `TopicProgressStore`
3. 根据 `JobDefinition` 找到需要检查的 Topic
4. 判断：
   - Lag 是否为 0（如果采用外部提供的 Lag 信息）
   - `journalSequence` 是否满足边界条件
   - `journalTimestamp` 是否满足规则（如果启用）
5. 生成一条完整的 **AuditResult**
6. 输出到 `snapshot-audit-topic`
7. 从 `MarkerStore` 删除已经完成判断的 Checkpoint（或更新其状态，取决于你的审计保留策略）

**这一步就是整个 CDC Snapshot Coordinator 的核心算法。**