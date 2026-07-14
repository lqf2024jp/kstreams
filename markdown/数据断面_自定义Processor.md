当然可以。

我建议你以后**不要再看书上的 `Yelling App`**，而是先学 **Processor API**，因为你的 CDC 项目最终基本都会用它。

下面给你一个**可以运行的最小完整示例**（Kafka Streams 3.x/4.x 风格）。

------

# 项目结构

```text
src
 └── main
      └── java
            ├── UpperCaseProcessor.java
            └── ProcessorDemo.java
```

------

# 第一步：自定义 Processor

```java
package demo;

import org.apache.kafka.streams.processor.api.ContextualProcessor;
import org.apache.kafka.streams.processor.api.Record;

public class UpperCaseProcessor
        extends ContextualProcessor<String, String, String, String> {

    @Override
    public void process(Record<String, String> record) {

        System.out.println("Receive : "
                + record.key()
                + " -> "
                + record.value());

        String upper = record.value().toUpperCase();

        context().forward(
                record.withValue(upper)
        );
    }
}
```

这里实际上只做了三件事：

```text
收到 Message

↓

处理 Message

↓

发送 Message
```

------

# 第二步：Main

```java
package demo;

import java.util.Properties;

import org.apache.kafka.common.serialization.Serdes;

import org.apache.kafka.streams.KafkaStreams;
import org.apache.kafka.streams.StreamsBuilder;
import org.apache.kafka.streams.StreamsConfig;

import org.apache.kafka.streams.processor.api.ProcessorSupplier;

public class ProcessorDemo {

    public static void main(String[] args) {

        Properties props = new Properties();

        props.put(
                StreamsConfig.APPLICATION_ID_CONFIG,
                "processor-demo");

        props.put(
                StreamsConfig.BOOTSTRAP_SERVERS_CONFIG,
                "localhost:9092");

        StreamsBuilder builder = new StreamsBuilder();

        builder
                .stream(
                        "src-topic"
                )
                .process(
                        new ProcessorSupplier<String, String, String, String>() {

                            @Override
                            public UpperCaseProcessor get() {
                                return new UpperCaseProcessor();
                            }
                        })
                .to(
                        "out-topic"
                );

        KafkaStreams streams =
                new KafkaStreams(builder.build(), props);

        streams.start();

        Runtime.getRuntime().addShutdownHook(
                new Thread(streams::close));
    }
}
```

------

# Kafka 里面的数据

例如：

```text
Topic

src-topic
```

里面：

| Key  | Value  |
| ---- | ------ |
| 1001 | apple  |
| 1002 | banana |
| 1003 | orange |

------

Processor：

收到：

```text
1001 apple
```

打印：

```text
Receive : 1001 -> apple
```

然后：

转换：

```text
APPLE
```

发送：

```text
out-topic
```

最终：

| Key  | Value  |
| ---- | ------ |
| 1001 | APPLE  |
| 1002 | BANANA |
| 1003 | ORANGE |

------

# 整个执行过程

```text
src-topic

1001 apple

      │

      ▼

UpperCaseProcessor

      │

record.value()

↓

apple

↓

toUpperCase()

↓

APPLE

      │

context.forward()

      │

      ▼

out-topic

1001 APPLE
```

------

# ContextualProcessor 到底是什么？

它其实就是：

```java
class ContextualProcessor<KIn, VIn, KOut, VOut>
```

四个泛型：

```java
ContextualProcessor<
        输入Key,
        输入Value,
        输出Key,
        输出Value>
```

例如：

这里：

```java
ContextualProcessor<
        String,
        String,
        String,
        String>
```

表示：

输入：

```text
1001

apple
```

输出：

```text
1001

APPLE
```

如果：

输出：

Long：

例如：

```java
ContextualProcessor<
        String,
        String,
        String,
        Long>
```

那么：

可以：

```text
apple

↓

长度

↓

5
```

------

# 为什么要

```java
context().forward(...)
```

因为：

Processor：

默认：

不会：

继续：

流。

例如：

```java
public void process(...) {

    String value = ...

}
```

如果：

没有：

```java
context().forward(...)
```

那么：

消息：

就在：

这里：

结束了。

不会：

进入：

下一个 Processor。

也不会：

写：

Kafka。

所以：

**forward() 就是"继续往后流"。**

------

# Processor API 真正的威力（也是你 CDC 项目真正会用到的）

刚才：

只是：

```java
String upper = record.value().toUpperCase();
```

但是：

以后：

你的项目：

会变成：

```java
public void process(Record<String, CdcMessage> record) {

    // 更新 TopicProgress
    topicStore.put(...);

    // 检查是否有等待中的 Marker
    checkPendingMarkers();

    // 如果满足条件
    context().forward(
            new Record<>(
                    checkpointId,
                    auditResult,
                    record.timestamp()
            ));
}
```

你会发现，它和 `Yelling App` 的 `mapValues()` 完全不是一个层次了。

------

## 我建议下一步我们不要再看书上的例子，而是直接写一个与你项目高度一致的示例：

**Processor API + StateStore**。

这个示例只有 **100 行左右**，但会实现：

- 收到业务 CDC 消息。
- 更新 `TopicProgress` 到 `StateStore`。
- 打印当前每个 Topic 的最新 `JournalSequence`。

这是你整个 CDC Snapshot Coordinator 的第一块核心代码，也是后续 Marker、Punctuator 等功能的基础。