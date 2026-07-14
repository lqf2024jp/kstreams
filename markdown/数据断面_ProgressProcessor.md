我建议我们直接写一个**第一版 CDC Snapshot Coordinator**，不要再写 `apple -> APPLE` 这种 Demo。

下面这个例子和你的项目已经有 **80% 相似**。

------

# 场景

假设只有两个业务表：

```text
ORDER_HEADER
ORDER_DETAIL
```

对应 Kafka Topic：

```text
order-header-topic
order-detail-topic
```

Kafka Message（已经解析成 Java 对象）：

```json
{
  "source": {
    "journalSequence": 1001,
    "journalTimestamp": "2026-07-12T13:00:01"
  }
}
```

我们的目标：

收到每条 CDC：

更新：

```text
StateStore

ORDER_HEADER
↓

1001

ORDER_DETAIL
↓

998
```

以后：

Marker

来了：

直接：

读取：

StateStore。

------

# Step1 Message

```java
public class CdcMessage {

    private Source source;

    public Source getSource() {
        return source;
    }

    public void setSource(Source source) {
        this.source = source;
    }
}
public class Source {

    private long journalSequence;

    private Instant journalTimestamp;

    public long getJournalSequence() {
        return journalSequence;
    }

    public void setJournalSequence(long journalSequence) {
        this.journalSequence = journalSequence;
    }

    public Instant getJournalTimestamp() {
        return journalTimestamp;
    }

    public void setJournalTimestamp(Instant journalTimestamp) {
        this.journalTimestamp = journalTimestamp;
    }
}
```

------

# Step2 Progress

StateStore：

保存：

```java
public class TopicProgress {

    private String topic;

    private long lastJournalSequence;

    private Instant lastJournalTimestamp;

    private Instant lastSeenTime;

    public TopicProgress() {
    }

    public TopicProgress(String topic,
                         long seq,
                         Instant ts,
                         Instant seen) {

        this.topic = topic;
        this.lastJournalSequence = seq;
        this.lastJournalTimestamp = ts;
        this.lastSeenTime = seen;
    }

    // getter setter
}
```

------

# Step3 Processor

这是：

整个项目：

最核心：

Processor。

```java
public class ProgressProcessor
extends ContextualProcessor<String,
                            CdcMessage,
                            String,
                            CdcMessage> {

    private KeyValueStore<String, TopicProgress> store;

    @Override
    public void init(
            ProcessorContext<String,CdcMessage> context) {

        super.init(context);

        store =
                context.getStateStore("topic-progress-store");
    }

    @Override
    public void process(
            Record<String,CdcMessage> record) {

        String topic =
                context().recordMetadata()
                         .get()
                         .topic();

        long seq =
                record.value()
                      .getSource()
                      .getJournalSequence();

        Instant journalTime =
                record.value()
                      .getSource()
                      .getJournalTimestamp();

        TopicProgress progress =
                new TopicProgress(
                        topic,
                        seq,
                        journalTime,
                        Instant.now());

        store.put(topic,progress);

        System.out.println(
                topic
                        +" -> "
                        +seq);

        context().forward(record);
    }

}
```

这里：

只有：

一句：

真正：

更新：

StateStore。

```java
store.put(topic,progress);
```

------

# Step4 注册 StateStore

Main：

```java
StoreBuilder<KeyValueStore<String,TopicProgress>>
storeBuilder =

Stores.keyValueStoreBuilder(

        Stores.persistentKeyValueStore(
                "topic-progress-store"),

        Serdes.String(),

        topicProgressSerde
);
```

然后：

```java
builder.addStateStore(storeBuilder);
```

------

Processor：

绑定：

```java
builder

.stream("order-header-topic")

.process(

ProgressProcessor::new,

"topic-progress-store"

);
```

DETAIL：

也是：

一样。

------

# 假设收到

第一条：

```json
ORDER_HEADER

Sequence=1001
```

Processor：

执行：

```text
store.put(

ORDER_HEADER,

1001
)
```

Store：

变成：

```text
ORDER_HEADER

↓

1001
```

------

然后：

收到：

```json
ORDER_DETAIL

998
```

Store：

变成：

```text
ORDER_HEADER

↓

1001

ORDER_DETAIL

↓

998
```

------

后来：

ORDER：

来了：

```json
1005
```

覆盖：

```text
ORDER_HEADER

↓

1005

ORDER_DETAIL

↓

998
```

StateStore：

永远：

保存：

最后：

一条。

------

# Marker Processor

以后：

Marker：

来了。

只需要：

```java
TopicProgress order =

store.get("order-header-topic");
```

得到：

```text
1005
```

DETAIL：

```java
store.get("order-detail-topic");
```

得到：

```text
998
```

然后：

开始：

判断。

------

# 整个 Topology

```text
                   order-header-topic
                           │
                           ▼
                  ProgressProcessor
                           │
                           ▼
                  TopicProgressStore
                           ▲
                           │
                   order-detail-topic
                           │
                           ▼
                  ProgressProcessor
```

Marker：

以后：

直接：

读：

```text
TopicProgressStore
```

------

# 这个版本还缺什么？

这个只是**第一版**。

还没有：

```text
MarkerStore
```

没有：

```text
Coordinator
```

没有：

```text
Punctuator
```

没有：

```text
Exactly Once
```

但是：

**已经是真正生产代码的第一步了。**

------

## 我建议我们不要一步一步学书，而是直接按照这个顺序把整个项目搭出来：

```text
① ProgressProcessor          ✅（今天）
        │
        ▼
② MarkerProcessor
        │
        ▼
③ SnapshotCoordinator
        │
        ▼
④ Punctuator（Timeout）
        │
        ▼
⑤ Audit Topic
        │
        ▼
⑥ GlobalKTable（动态 Job 配置）
        │
        ▼
⑦ Exactly Once
```

到第⑦步结束时，你会得到一个完整的 **CDC Snapshot Coordinator**，它已经远远超过《Kafka Streams 实战》第三章的示例，也足以作为一个真实企业级项目。