这段 Yelling App 是《Kafka Streams 实战》第三章的第一个完整示例，它的目标非常简单：

从 Kafka 的 src-topic 读取文本，把 value 转成大写，再写入 out-topic，同时打印到控制台。

### 先看整体流程

src-topic

原始文本

toUpperCase

转换

out-topic

大写文本

控制台

print![image-20260712133630516](C:\Users\User\AppData\Roaming\Typora\typora-user-images\image-20260712133630516.png)

### 逐段解释代码

### 1. 生成测试数据

代码

这是作者为了演示方便写的 模拟生产者。

它会向 src-topic 持续发送随机文本，例如：

Key

Value

1

hello kafka

2

streams are fun

3

java rocks

实际生产环境一般不会在 Streams 程序里自己生产数据。

### 2. 配置 Kafka Streams

代码

### 关键配置

| 配置项            | 作用                       |
| ----------------- | -------------------------- |
| application.id    | 消费者组 ID + 状态存储前缀 |
| bootstrap.servers | Kafka Broker 地址          |

### 这里的 application.id 很重要

Kafka Streams 会自动：

- 创建消费者组 `yelling_app_id`
- 记录消费位点（offset）
- 管理任务分配
- 支持故障恢复

### 3. 定义序列化器（Serde）

代码

Serde = Serializer + Deserializer

告诉 Kafka：

- Key 是 `String`
- Value 也是 `String`

因为 Topic 中存储的是字节数组，Streams 需要知道如何把字节转换成 Java 对象。

### 4. 创建拓扑（Topology）

代码

StreamsBuilder 用来构建数据处理拓扑图。

可以理解为：

builder = “画数据流图的工具”

### 5. 从 Topic 创建 KStream

代码

### 含义

读取 `src-topic` 中的数据。

### 类型

```
KStream<String, String>
```

表示：

- Key 类型：`String`
- Value 类型：`String`

### 为什么叫 KStream？

KStream 代表“事件流”：

- 每条消息都是独立事件
- 不会自动按 Key 聚合
- 适合日志、订单、点击流等场景

### 6. 核心转换：变成大写

代码

### 这是本章最重要的一行

`mapValues` 的意思：

只修改 Value，不修改 Key

### 等价写法

### 转换前后

| 输入            | 输出            |
| --------------- | --------------- |
| hello kafka     | HELLO KAFKA     |
| streams are fun | STREAMS ARE FUN |

### 注意

`mapValues` 不会改变分区，因为 Key 没变。

如果用 `map` 修改了 Key，则可能触发 重新分区（repartition）。

### 7. 写回 Kafka

代码

把处理后的结果写入 out-topic。

### 结果

src-topic：`hello kafka`

out-topic：`HELLO KAFKA`

### 8. 打印到控制台

代码

控制台会输出类似：

Yelling App: 1, HELLO KAFKA

Yelling App: 2, STREAMS ARE FUN

这只是调试功能，生产环境通常不会大量使用。

### 9. 启动 Streams 应用

代码

### 这里发生了什么？

`builder.build()` 会生成真正的 Topology。

内部大致是：

SOURCE(src-topic)

│

MAPVALUES(toUpperCase)

│

SINK(out-topic)

然后 `start()`：

- 创建消费者
- 订阅 `src-topic`
- 拉取消息
- 执行 `toUpperCase`
- 发送到 `out-topic`

### 10. 为什么 sleep 35 秒？

代码

只是为了让示例程序运行 35 秒。

真实项目中通常是：

让应用一直运行。

### 完整的数据流示例

### 输入（src-topic）

Kafka

| Key  | Value           |
| ---- | --------------- |
| 1    | hello kafka     |
| 2    | streams are fun |

### 处理逻辑

mapValues

hello kafka

toUpperCase()

HELLO KAFKA

### 输出（out-topic）

Kafka

| Key  | Value           |
| ---- | --------------- |
| 1    | HELLO KAFKA     |
| 2    | STREAMS ARE FUN |

### 这个例子真正想教你的是什么？

### Kafka Streams 的核心编程模型

重点

1

builder.stream()

从 Topic 创建流

2

mapValues()

对流进行转换

3

to()

把结果写回 Topic

4

start()

启动持续处理

### 与 Flink 的对应关系（你现在学习的重点）

| Kafka Streams        | Flink            |
| -------------------- | ---------------- |
| builder.stream()     | env.fromSource() |
| mapValues()          | map()            |
| to()                 | sinkTo()         |
| KafkaStreams.start() | env.execute()    |

### 你可以把这个 Yelling App 理解成：

Kafka Streams 版的 “Hello World”

它用最少的代码展示了 Source → Transform → Sink 这一条完整的数据流处理链路。

### 下一步最值得看的

如果你愿意，我可以继续帮你把 第 3 章后半部分的 WordCount 示例 也拆开，并重点解释 groupByKey → count → KTable 是如何工作的——这正是 Kafka Streams 和 Flink 在“有状态计算”上的核心思想。

这段 Yelling App（大喊应用） 是《Kafka Streams 实战》第三章的第一个完整 Kafka Streams 程序。它的作用非常简单：

从 Kafka 的 src-topic 读取文本 → 转成大写 → 写入 out-topic → 同时打印到控制台。

### 先把它想象成一条流水线

src-topic

hello kafka

mapValues

toUpperCase()

out-topic

HELLO KAFKA

控制台输出

Yelling App

HELLO KAFKA

这就是 Kafka Streams 的核心思想：把 Topic 当作数据流来处理。

### 第一幕：准备测试数据

### 第 1 行

测试代码

这行代码会启动一个 模拟生产者，向 src-topic 不断发送随机文本，例如：

src-topic

key1 → hello kafka

key2 → streams are cool

key3 → good morning

真实项目中通常不会这样写。

生产者一般是独立的应用，这里只是为了演示方便。

### 第二幕：配置 Kafka Streams

### 代码

### 两个最重要的配置

| 配置项                                 | 作用                         |
| -------------------------------------- | ---------------------------- |
| APPLICATION_ID_CONFIGyelling_app_id    | Kafka Streams 应用的唯一标识 |
| BOOTSTRAP_SERVERS_CONFIGlocalhost:9092 | Kafka 集群地址               |

### 为什么 Application ID 很重要？

它不仅是应用名，还决定了：

- Consumer Group 名称
- 状态存储（State Store）目录
- 内部 Topic 名称
- 故障恢复行为

可以把它理解成：整个 Streams 拓扑（Topology）的身份证。

### 第三幕：声明序列化方式

Kafka 中的数据本质上是 byte[]。

这里告诉 Streams：

- Key 是 String
- Value 也是 String

后面读写 Topic 时都会用到它。

### 第四幕：创建数据流

这一行非常关键：

Kafka Topic

Java 对象流

src-topic

KStream<String,String>

(key,value)

此时 Streams 已经把 Kafka Topic 抽象成了一个 无限流（unbounded stream）。

### 第五幕：真正的业务逻辑

这是 Java 8 的方法引用，等价于：

### 注意：为什么是 mapValues？

| 方法        | 会修改 Key 吗？ |
| ----------- | --------------- |
| map()       | 会              |
| mapValues() | 不会            |

### 输入输出示例

| 输入       | 输出       |
| ---------- | ---------- |
| k1 → hello | k1 → HELLO |
| k2 → kafka | k2 → KAFKA |

Key 完全保留，只转换 Value。

### 第六幕：写回 Kafka

现在数据被写入新的 Topic：

src-topic

out-topic

hello kafka

HELLO KAFKA

✓

这就是一个典型的 Source → Processor → Sink 拓扑。

### 第七幕：打印到控制台

运行时你会看到类似输出：

[Yelling App]: k1, HELLO KAFKA

[Yelling App]: k2, STREAMS ARE COOL

[Yelling App]: k3, GOOD MORNING

仅用于调试和学习，生产环境通常不会大量使用 print()。

### 第八幕：启动 Streams 引擎

builder.build() 会把前面的流操作组装成一张拓扑图。

### 内部拓扑（概念）

Source Node

读取 src-topic

Processor Node

mapValues(toUpperCase)

Sink Node

写入 out-topic

start() 之后，Streams 会：

- 创建 Kafka Consumer
- 订阅 src-topic
- 持续拉取消息
- 执行大写转换
- 写入 out-topic

### 第九幕：为什么只运行 35 秒？

作者为了演示方便：

- 运行 35 秒
- 自动关闭
- 停止模拟生产者

真实应用通常会：

一直运行

### 把整段代码浓缩成 5 行

这就是 Kafka Streams 的魅力：

不需要手写 Consumer 循环

不需要手写 Producer 发送

不需要管理 offset 提交

只描述 “数据如何流动”

### 结合你现在的学习路线（Kafka → Debezium → Streams）

你可以把这个 Yelling App 看成 Kafka Streams 的 Hello World。

### 下一步最值得做的升级版

过滤空消息

filter((k,v) -> v != null)

按单词拆分

flatMapValues(...)

统计词频

groupBy + count

输出 Top N 热词

实时分析

接入 Debezium CDC

处理数据库变更事件

### 这时就从“玩具示例”进入真正的实时数据处理了。

而你前面问到的 事务一致性、Transaction Metadata、多表 CDC，都会在 Streams 的聚合和状态管理 章节里真正发挥作用。

-----

-----

这是很多初学 Kafka Streams 的人都会困惑的地方。实际上，这两句代码属于**两个完全不同的阶段**：

- `builder.stream(...)`：**定义数据处理逻辑（画流程图）**
- `new KafkaStreams(...)`：**创建并运行这个流程图（启动引擎）**

可以把它理解成"编写 SQL"和"执行 SQL"的区别。

------

# 第一句：builder.stream()

```java
KStream<String, String> simpleFirstStream =
    builder.stream("src-topic", Consumed.with(stringSerde, stringSerde));
```

这里**没有开始消费 Kafka**。

它只是告诉 `StreamsBuilder`：

> "以后我要从 `src-topic` 读取数据。"

它返回一个 **KStream 对象**。

这个 KStream 并不是数据，而是一个**流的描述（DSL 对象）**。

可以理解为：

```
src-topic
    │
    ▼
simpleFirstStream
```

此时 Kafka 没有连接。

Broker 没有收到任何请求。

Consumer 也没有创建。

------

## 可以继续往后"画"

例如：

```java
KStream<String,String> upper =
    simpleFirstStream.mapValues(String::toUpperCase);

upper.filter(...);

upper.flatMap(...);

upper.to("out-topic");
```

这些都只是不断在 Builder 里增加节点。

越来越像这样：

```
src-topic
      │
      ▼
 mapValues
      │
      ▼
 filter
      │
      ▼
 out-topic
```

还是没有运行。

------

# builder.build()

当执行

```java
Topology topology = builder.build();
```

Builder 会把前面画好的流程图生成一个真正的 **Topology**。

例如：

```
Source(src-topic)

↓

mapValues

↓

Sink(out-topic)
```

注意：

**Topology 仍然没有运行。**

它只是一个对象。

------

# 第二句：new KafkaStreams()

```java
KafkaStreams kafkaStreams =
    new KafkaStreams(builder.build(), streamsConfig);
```

这里发生的是：

把刚才生成的 Topology 交给 Kafka Streams Runtime。

它类似于：

```
Topology
      │
      ▼
KafkaStreams Runtime
```

但是此时仍然没有开始消费。

因为还没有：

```java
kafkaStreams.start();
```

------

# 真正开始工作的是 start()

```java
kafkaStreams.start();
```

这一句才会：

① 创建 KafkaConsumer

```
KafkaConsumer
```

↓

② 加入 Consumer Group

```
yelling_app_id
```

↓

③ 获取 Partition

```
src-topic-0
src-topic-1
```

↓

④ 开始 poll()

```
poll()

poll()

poll()
```

↓

⑤ 每收到一条消息

```
hello

↓

mapValues()

↓

HELLO

↓

Producer.send()

↓

out-topic
```

这时整个程序才真正运行起来。

------

# 三者关系

```
builder.stream()

↓

定义 Source


mapValues()

↓

定义 Processor


to()

↓

定义 Sink


builder.build()

↓

生成 Topology


new KafkaStreams()

↓

创建运行实例


start()

↓

真正开始消费 Kafka
```

------

# 和 Spring Boot 作个类比

Spring Boot 中：

```java
@Bean
public DataSource ds() {}
```

只是定义 Bean。

真正实例化是在：

```java
SpringApplication.run(...)
```

Kafka Streams 也一样：

```
builder.stream()

↓

定义 Bean（流程）


builder.build()

↓

ApplicationContext


KafkaStreams.start()

↓

Spring 容器启动
```

------

# 再和 Flink 对比（你现在正在学习 Kind、Kafka、Flink，这个类比很重要）

Kafka Streams：

```java
StreamsBuilder builder = new StreamsBuilder();

builder.stream(...);

mapValues(...);

to(...);

KafkaStreams streams =
    new KafkaStreams(builder.build(), props);

streams.start();
```

Flink：

```java
StreamExecutionEnvironment env =
    StreamExecutionEnvironment.getExecutionEnvironment();

DataStream<String> stream = env.fromSource(...);

stream.map(...);

stream.sinkTo(...);

env.execute();
```

对应关系如下：

| Kafka Streams           | Flink                                     | 作用         |
| ----------------------- | ----------------------------------------- | ------------ |
| `builder.stream()`      | `env.fromSource()`                        | 定义数据源   |
| `mapValues()`           | `map()`                                   | 定义转换逻辑 |
| `to()`                  | `sinkTo()`                                | 定义输出     |
| `builder.build()`       | 构建 Job Graph（内部过程）                | 生成执行计划 |
| `new KafkaStreams(...)` | 创建 `StreamGraph`/`JobClient` 等运行对象 | 准备运行环境 |
| `start()`               | `env.execute()`                           | 真正启动作业 |

所以，你可以记住一句话：

- **`builder.stream()` 是在"画图"（声明处理拓扑）。**
- **`builder.build()` 是把图转换成可执行的拓扑对象。**
- **`new KafkaStreams(...)` 是创建执行这个拓扑的运行时实例。**
- **`start()` 才是真正连接 Kafka、消费消息并开始处理数据。**

这种**先声明拓扑、后统一启动执行**的设计，是 Kafka Streams DSL 的核心，也是它与 Flink、Spark Structured Streaming 等现代流处理框架共同采用的编程模式。

----

这是 Kafka Streams DSL 中最核心的概念之一。**`simpleFirstStream.mapValues(...)` 并不是在立即处理数据，而是在给这条数据流添加一个新的处理节点。**

先看这行代码：

```java
KStream<String, String> upperCasedStream =
    simpleFirstStream.mapValues(String::toUpperCase);
```

很多人第一次看到会以为：

> "simpleFirstStream 里面已经有很多数据了，现在把它们全部变成大写。"

**实际上完全不是。**

------

# KStream 不是数据，而是"数据流"

假设 Kafka 里有：

```
src-topic

Key    Value
----------------
1      hello
2      kafka
3      streams
```

执行：

```java
builder.stream("src-topic")
```

并不会把这些数据读进来。

而是得到一个对象：

```java
simpleFirstStream
```

它表示：

> **以后从 src-topic 流出来的数据，都属于这条流。**

可以画成：

```
src-topic

↓

simpleFirstStream
```

------

# mapValues 在做什么？

然后：

```java
simpleFirstStream.mapValues(String::toUpperCase)
```

意思是：

> **以后经过这里的每一条消息，都执行一次 `toUpperCase()`。**

注意关键词：

> **以后**

不是现在。

不是一次性。

不是遍历。

而是：

> 每来一条，就处理一条。

所以拓扑变成：

```
src-topic

↓

simpleFirstStream

↓

mapValues(toUpperCase)

↓

upperCasedStream
```

------

# 为什么返回一个新的 KStream？

很多 Java 初学者会疑惑：

为什么不是：

```java
simpleFirstStream.mapValues(...);
```

而是：

```java
KStream<String,String> upper =
    simpleFirstStream.mapValues(...);
```

因为：

**Kafka Streams 的 KStream 是不可变（Immutable）的。**

原来的：

```
simpleFirstStream
```

仍然存在。

mapValues 返回的是：

```
upperCasedStream
```

新的流。

就像 Java Stream：

```java
List<String> upper =
    list.stream()
        .map(String::toUpperCase)
        .toList();
```

map() 不会修改原来的 List。

------

# 实际运行时发生什么？

假设 Kafka 收到：

```
hello
```

数据流经过：

```
Source

↓

simpleFirstStream

↓

mapValues

↓

Sink
```

运行时：

```
收到：

hello

↓

执行

String::toUpperCase

↓

HELLO

↓

发送到 out-topic
```

如果又来：

```
kafka
```

再执行一次：

```
kafka

↓

toUpperCase()

↓

KAFKA
```

整个过程就是：

```
消息1

↓

Processor

↓

输出


消息2

↓

Processor

↓

输出


消息3

↓

Processor

↓

输出
```

而不是：

```
把 Topic 全部读出来

↓

全部转换

↓

一次写回
```

------

# mapValues 为什么叫 mapValues？

因为 Kafka 的消息有：

```
Key

Value
```

例如：

```
Key = user001

Value = hello
```

执行：

```java
mapValues(String::toUpperCase)
```

得到：

```
Key = user001

Value = HELLO
```

可以看到：

**Key 完全没有变。**

只有 Value 被修改。

------

# 如果想修改 Key 呢？

那就不能用：

```java
mapValues(...)
```

而要用：

```java
map(...)
```

例如：

```java
stream.map((key, value) ->
    KeyValue.pair(
        key.toUpperCase(),
        value.toUpperCase()
    ));
```

这时：

```
user001

↓

USER001
```

Key 改了。

------

# 为什么 Kafka Streams 专门提供 mapValues？

因为**修改 Value 非常常见，而且比修改 Key 更高效**。

原因在于 Kafka 的分区是根据 **Key** 决定的。

例如：

```
Partition = hash(Key)
```

如果：

```
Key 不变
```

那么：

```
Partition 不变
```

Kafka Streams 不需要重新分区（repartition）。

所以：

```
mapValues
```

只是：

```
Processor

↓

修改 Value

↓

继续往下流
```

效率非常高。

而：

```
map()
```

如果修改了 Key：

```
Processor

↓

Key 改变

↓

重新计算 Partition

↓

Repartition Topic

↓

继续处理
```

就可能触发额外的网络传输和内部 Topic。

------

## 用一句话总结

`simpleFirstStream.mapValues(...)` 的本质不是“把数据变大写”，而是**在拓扑中添加一个只修改 Value 的 Processor 节点**。真正的数据处理要等到 `kafkaStreams.start()` 后，每当一条消息流经这个节点时，才会调用一次 `toUpperCase()`。

对于这段代码：

```java
builder.stream("src-topic")
       .mapValues(String::toUpperCase)
       .to("out-topic");
```

可以把它理解成一条流水线：

```
src-topic
     │
     ▼
 Source
     │
     ▼
 mapValues(toUpperCase)
     │
     ▼
 out-topic
```

每条消息都会依次经过这条流水线，而不是一次性处理整个 Topic。这种**按记录、持续流动**的处理方式，就是 Kafka Streams 编程模型的核心。

这是一个非常好的问题，而且**很多人第一次学 Kafka Streams 都会误以为顺序决定执行顺序**。

实际上，这两句：

```java
upperCasedStream.to("out-topic");

upperCasedStream.print(
    Printed.<String,String>toSysOut()
        .withLabel("Yelling App"));
```

**谁写前、谁写后，通常都没有区别。**

原因是：

> **你不是在"执行"代码，而是在"构建拓扑（Topology）"。**

------

## 很多人会这样理解（实际上是错的）

看到代码：

```java
upperCasedStream.to("out-topic");
upperCasedStream.print(...);
```

容易认为：

```
先写 Kafka

↓

再打印
```

好像消息会先进入 `out-topic`，然后再打印。

**实际上不是。**

------

## 实际的拓扑

当执行：

```java
upperCasedStream.to("out-topic");
```

Builder 加了一个 Sink 节点：

```
upperCasedStream

↓

Sink(out-topic)
```

然后：

```java
upperCasedStream.print(...);
```

Builder 又加了一个 Processor（Print 节点）：

```
upperCasedStream

├────────► Sink(out-topic)

└────────► Print(System.out)
```

注意：

这里出现了**分叉（Branch）**。

不是：

```
to

↓

print
```

而是：

```
             upperCasedStream
                    │
        ┌───────────┴───────────┐
        ▼                       ▼
   Sink(out-topic)         Print(console)
```

这两个节点都连接到 **同一个 `upperCasedStream`**。

------

## 所以交换顺序也一样

如果写成：

```java
upperCasedStream.print(...);

upperCasedStream.to("out-topic");
```

最终拓扑仍然是：

```
             upperCasedStream
                    │
        ┌───────────┴───────────┐
        ▼                       ▼
   Print(console)         Sink(out-topic)
```

Builder 只是把两个子节点都挂到同一个父节点下面。

------

## 为什么 `to()` 没有返回值？

注意：

```java
upperCasedStream.to(...);
```

返回的是：

```java
void
```

因此：

```java
upperCasedStream
```

仍然存在。

所以还能继续：

```java
upperCasedStream.print(...);

upperCasedStream.foreach(...);

upperCasedStream.peek(...);
```

它们都是从同一个流派生出来的。

------

## 如果想真正做到"先 to 再 print"怎么办？

实际上做不到，因为：

```java
to()
```

已经是 Sink。

Sink 后面不能继续接 Processor。

例如：

```java
stream
    .mapValues(...)
    .to(...)
    .print(...)
```

这种写法根本不存在，因为：

```java
to()
```

返回 `void`。

------

## 为什么 Kafka Streams 要这样设计？

因为一条流经常需要：

- 写 Kafka
- 打日志
- 发邮件
- 写数据库
- 更新缓存

例如：

```
             Payment Stream
                    │
        ┌───────────┼────────────┐
        ▼           ▼            ▼
   Kafka Topic    MySQL       Audit Log
```

同一份数据可以同时流向多个下游，而不用复制处理逻辑。

------

## 总结

这两句代码：

```java
upperCasedStream.to("out-topic");
upperCasedStream.print(...);
```

不是"先写 Topic，再打印"，而是**在拓扑中为 `upperCasedStream` 增加了两个独立的下游节点**。它们都消费同一条流，彼此没有依赖关系，所以**代码先后顺序通常不会影响处理逻辑**。

你已经开始关注 Kafka Streams 的**拓扑结构**而不是 Java 代码的执行顺序了，这是学习 Kafka Streams 最重要的思维转变。后面学习 `branch()`、`split()`、`join()` 时，这种"一条流可以分出多个下游"的模型会更加常见。

---

**完全正确。**

`to("out-topic")` **不是必须的**。

如果你的目的只是观察数据，完全可以只写：

```java
KStream<String, String> upperCasedStream =
    simpleFirstStream.mapValues(String::toUpperCase);

upperCasedStream.print(
    Printed.<String, String>toSysOut()
        .withLabel("Yelling App")
);
```

程序一样可以正常运行。

------

## 数据流变成这样

```
src-topic
     │
     ▼
Source
     │
     ▼
mapValues
     │
     ▼
Print(System.out)
```

当 Kafka 收到：

```
hello
```

控制台输出：

```
Yelling App: null, HELLO
```

（假设 Key 是 `null`）

但是 **`out-topic` 不会有任何消息**。

------

## 为什么书里还要写 `to()`？

因为作者想演示 Kafka Streams 最典型的用途：

```
Kafka Topic
      │
      ▼
Kafka Streams
      │
      ▼
Kafka Topic
```

也就是：

```
src-topic
      │
      ▼
Streams App
      │
      ▼
out-topic
```

后面的应用可以继续消费 `out-topic`。

例如：

```
Producer
     │
     ▼
src-topic
     │
     ▼
Yelling App
     │
     ▼
out-topic
     │
     ▼
WordCount App
     │
     ▼
统计结果
```

这就是 Kafka 非常经典的**流式处理管道（Streaming Pipeline）**。

------

## `print()` 的作用

`print()` 主要用于：

- 调试
- 学习
- 验证处理结果

例如开发时：

```java
stream
    .mapValues(...)
    .print(...);
```

确认结果正确后，通常会改成：

```java
stream
    .mapValues(...)
    .to("out-topic");
```

生产环境一般不会一直打印大量消息到控制台，因为这会影响性能，而且日志很快会被刷满。

------

## 更进一步：如果两者都不要呢？

例如：

```java
builder.stream("src-topic")
       .mapValues(String::toUpperCase);
```

这里只有 **Source → mapValues**，没有任何下游（Sink 或终端处理）。

从拓扑角度看：

```
Source
   │
   ▼
mapValues
```

这个结果没有任何地方消费，等于你定义了一个处理节点，却没有把结果输出到任何地方。一般来说，这样的代码没有实际意义。

------

## 一个形象的比喻

可以把 `KStream` 想成一条自来水管：

```
src-topic
     │
     ▼
  水管
```

`mapValues()` 是安装一个过滤器：

```
水源
 │
 ▼
过滤器
```

但过滤后的水要流向哪里？

- `to()`：流进另一个水箱（Kafka Topic）
- `print()`：流到一个透明容器里供你观察（控制台）
- `foreach()`：流到你自己写的处理逻辑

如果既没有 `to()`、也没有 `print()`、也没有其他下游，那么就像水管末端没有接任何东西，这段处理通常就没有实际价值。

------

所以你的理解是对的：

- ✅ **只打印：** 不需要 `to()`。
- ✅ **只写 Kafka：** 不需要 `print()`。
- ✅ **既打印又写 Kafka：** 两个都可以保留，它们会作为 `upperCasedStream` 的两个独立下游同时接收处理后的消息。

---

这里要区分两个产品，因为它们的消息格式完全不同：

1. **Debezium for Db2**（开源）
2. **IBM InfoSphere / IBM Data Replication (CDC for IBM i)**（IBM 商业产品）

你问的是：

> **"使用 IBM CDC for i 的库，给我完整的带 source 的 message"**

实际上，**IBM CDC for i 默认并不会生成 Debezium 那种 `before/after/source/op` 的 Envelope。** 它发送的是 IBM CDC 自己定义的消息格式（或者直接复制到目标数据库），而不是 Debezium Event。IBM CDC 提供的 Journal 信息通常通过 **Journal Control Fields**（例如 `&JOURNAL`、`&SEQNO`、`&CCID` 等）映射到目标列，而不是自动放到 Kafka 消息的 `source` 对象里。([IBM](https://www.ibm.com/docs/en/idr/11.3.3?topic=console-using-journal-control-fields-auditing-replication-activities&utm_source=chatgpt.com))

------

## 如果你的 Kafka 消息是 IBM CDC 自定义封装

很多项目会自己封装成下面这种格式（**这是企业常见做法，不是 IBM 默认 JSON**）：

```json
{
  "before": {
    "ORDER_ID": 10001,
    "STATUS": "N"
  },
  "after": {
    "ORDER_ID": 10001,
    "STATUS": "S"
  },
  "source": {
    "system": "AS400-PROD",
    "library": "SALESLIB",
    "table": "ORDER_HEADER",

    "journal_library": "JRNLIB",
    "journal_name": "ORDJRN",
    "journal_receiver": "ORDRCV000123",

    "sequence_number": 3456789123,
    "entry_type": "UP",
    "transaction_id": "0000000012345678",

    "job": "QPADEV0001",
    "user": "APPUSER",
    "program": "ORDUPD",

    "timestamp": "2026-07-12T13:58:10.123456"
  },
  "op": "u"
}
```

这个 JSON 非常符合 IBM i 的思维方式，因为它把 Journal 的定位信息都保留下来了。

------

## IBM CDC 真正提供的 Journal Control Fields

IBM CDC for i 可以提供（或映射）很多 Journal Control Fields，例如：([IBM](https://www.ibm.com/docs/en/idr/11.3.3?topic=exit-retrieving-journal-control-fields-using-j-prefix&utm_source=chatgpt.com))

| Journal Field | 含义                                         |
| ------------- | -------------------------------------------- |
| `&JOURNAL`    | Journal 名称（某些版本包含 Journal Library） |
| `&JRNLIB`     | Journal Library（部分引擎支持）              |
| `&SEQNO`      | Journal Sequence Number                      |
| `&CCID`       | Transaction ID                               |
| `&ENTTYP`     | Entry Type（UP、UB、DL、PT 等）              |
| `&TIMSTAMP`   | Journal Timestamp                            |
| `&USER`       | OS User                                      |
| `&PROGRAM`    | 更新程序                                     |
| `&JOB`        | Job Name                                     |
| `&SYSTEM`     | Source System                                |
| `&MEMBER`     | Source Physical File Member                  |

所以如果你希望以后审计能够精确定位 Journal，一般都会把这些字段一起带下来。

------

## 如果你问的是"IBM CDC Kafka Adapter 默认发出来的 JSON"

那答案是：

**没有一个统一的标准 JSON。**

IBM CDC 支持多种目标：

- Db2
- Oracle
- PostgreSQL
- MQ
- Kafka
- 自定义 Exit

Kafka 的消息内容可以配置：

- JSON
- XML
- Delimited
- 自定义 User Exit

**也就是说，IBM 官方没有像 Debezium 那样固定的 Envelope Schema。**([IBM](https://www.ibm.com/docs/en/idr/11.3.3?topic=console-using-journal-control-fields-auditing-replication-activities&utm_source=chatgpt.com))

------

### 我想确认一下你的项目

你之前一直说的是：

> **AS400 Db2 i → Debezium → Kafka → PostgreSQL**

但这次又提到：

> **"使用 IBM CDC for i 的库"**

这里有两种完全不同的架构：

1. **Debezium + Kafka Connect**（开源）
2. **IBM InfoSphere CDC / IBM Data Replication (IIDR)**（商业版）

**你们实际项目使用的是哪一种？**

- 如果是 **IBM InfoSphere CDC（IIDR）**，我可以给你画出它真实的 Journal → Kafka Message 流程，并列出 IBM CDC Kafka Adapter 实际可配置的字段。
- 如果是 **Debezium for IBM i（或基于 IBM i Journal 的 Debezium Connector）**，那消息格式就是另一套。

----

这是一个非常好的问题，因为 **CDC 里面实际上至少有 3～4 种时间**，很多项目都会混淆。

你这个 `source.timestamp`（如果是 IBM CDC 自己带出来的 Journal 时间）**应该理解为：**

> **AS400（IBM i）Journal Entry 写入 Journal 的时间。**

也就是说，它来源于 **IBM i Journal**，不是 Kafka 时间，也不是 PostgreSQL 时间。

------

## 一次 UPDATE 会经历几个时间？

例如：

```sql
UPDATE ORDER_HEADER
SET STATUS='S'
WHERE ORDER_ID=10001;
```

整个流程：

```text
13:58:10.123456
      │
      │ ① SQL Commit
      ▼
AS400 Db2 for i
      │
      │
      ▼
Journal Entry
(timestamp = 13:58:10.123456)
      │
      │
      ▼
IBM CDC
      │
      │ 读取 Journal
      ▼
Kafka Producer
      │
      │
      ▼
Kafka Broker
(LogAppendTime 或 CreateTime)
      │
      ▼
Kafka Topic
      │
      ▼
PostgreSQL
```

因此这里至少有 4 个时间。

------

# ① Journal Timestamp（最重要）

例如：

```json
"source": {
    "timestamp":"2026-07-12T13:58:10.123456"
}
```

它表示：

> **Journal Entry 被写入 IBM i Journal 的时间。**

来源：

```text
IBM i

↓

Journal Entry Header

↓

Timestamp
```

它反映的是数据库事务发生的时间。

------

# ② Kafka Message Timestamp

Kafka 自己也有：

```text
Message Timestamp
```

例如：

```
2026-07-12 13:58:10.321
```

它来自：

Producer：

```
CreateTime
```

或者：

Broker：

```
LogAppendTime
```

取决于 Topic 配置。

通常会比 Journal 慢几十毫秒到几秒。

例如：

```
Journal

13:58:10.123

↓

CDC

↓

Kafka

13:58:10.341
```

------

# ③ PostgreSQL 时间

例如：

```sql
updated_at
```

或者：

```sql
CURRENT_TIMESTAMP
```

例如：

```
13:58:11
```

这是：

Sink 写 PostgreSQL 的时间。

可能已经过去：

```
500ms

2 秒

10 秒
```

甚至：

```
5 分钟
```

------

# ④ Kafka Connect / CDC Capture Time

有些 CDC 产品还会记录：

```
CDC Read Time
```

例如：

```
13:58:10.280
```

表示：

CDC Engine

从 Journal

读取到这一条日志

的时间。

不是事务时间。

------

# 举个真实例子

例如：

```
13:58:10.100

用户点击发货
```

↓

```
13:58:10.123

Db2 Commit
```

↓

```
13:58:10.123

Journal Entry Timestamp
```

↓

```
13:58:10.250

IBM CDC Read
```

↓

```
13:58:10.310

Kafka Producer Send
```

↓

```
13:58:10.335

Kafka Broker Append
```

↓

```
13:58:10.580

PostgreSQL Commit
```

你会发现：

整个链路有 **5 个不同时间**。

------

# 企业一般保留哪个？

做 CDC 延迟监控时，一般都会保留：

| 时间              | 来源       | 用途               |
| ----------------- | ---------- | ------------------ |
| Journal Timestamp | IBM i      | 业务真实发生时间   |
| Kafka Timestamp   | Kafka      | Kafka 排队延迟分析 |
| Sink Timestamp    | PostgreSQL | 同步完成时间       |

这样就能计算：

```
Kafka 延迟

=

Kafka Time

-

Journal Time
```

以及：

```
同步延迟

=

PostgreSQL Time

-

Journal Time
```

------

## 针对你的项目（AS400 → Kafka → PostgreSQL）

如果我是设计这套同步系统，我会在 Kafka 消息里同时保留这几个时间，例如：

```json
{
  "source": {
    "journal_timestamp": "2026-07-12T13:58:10.123456",
    "journal_sequence": 3456789123,
    "journal_name": "ORDJRN"
  },
  "cdc": {
    "capture_timestamp": "2026-07-12T13:58:10.251000"
  },
  "kafka": {
    "producer_timestamp": "2026-07-12T13:58:10.310000"
  }
}
```

这样以后任何延迟问题都能定位。

------

**所以，你这里的 `source.timestamp` 最合理、也是 IBM i Journal 最有价值的定义应该是：**

> **Db2 for i 事务提交后写入 Journal Entry 的时间（Journal Timestamp）**。

它**属于 AS/400（IBM i）的时间**，不是 Kafka 的时间，也不是 PostgreSQL 的时间。对于做 CDC 审计、延迟分析和故障排查，这个时间通常是最重要的"基准时间"。

----

journal_timestamp

**这个问题已经问到 IBM i Journal 的核心了。**

答案是：

> **是的，`sequence_number` 只能在同一个 Journal 内比较；而 `journal_timestamp` 可以跨 Journal 比较，但不能把它当成严格的全局顺序。**

下面分别解释。

------

# 1. sequence_number

例如：

```text
JRNLIB1/ORDJRN

Sequence

1001
1002
1003
1004
```

另一个 Journal：

```text
JRNLIB2/CUSTJRN

Sequence

1
2
3
4
```

显然：

```text
ORDJRN 1003

>

CUSTJRN 2
```

**没有任何意义。**

因为：

它们属于两个完全不同的 Journal。

所以：

**Sequence Number 的比较范围只有一个 Journal。**

一般定位都需要：

```text
Journal Library
Journal Name
Sequence Number
```

三者一起。

------

# 2. Journal Timestamp

Journal Timestamp 不一样。

例如：

```text
ORDJRN

13:58:10.123456
```

另一个：

```text
CUSTJRN

13:58:10.456789
```

它们都是 IBM i 系统时间。

因此：

```text
13:58:10.123

<

13:58:10.456
```

这个比较是成立的。

------

## 为什么成立？

因为 IBM i 整个 LPAR（系统）只有一套系统时钟。

例如：

```text
IBM i

↓

System Clock

↓

所有 Journal
```

所有 Journal Entry 的 Timestamp 都来自：

```text
QTIME
```

（准确来说来自系统时间，而不是每个 Journal 自己维护时间。）

所以：

不同 Journal 的 Timestamp 可以放在时间线上。

------

# 3. 但是不能认为它就是全局顺序

例如：

CPU1：

```text
13:58:10.123456

UPDATE ORDER
```

CPU2：

```text
13:58:10.123456

UPDATE CUSTOMER
```

两个 Journal：

```text
ORDJRN

13:58:10.123456
CUSJRN

13:58:10.123456
```

时间一样。

但是：

到底谁先？

不知道。

因为：

- 时间精度有限（虽然 IBM i 很高）
- 多 CPU 并发
- Journal 是独立写入的

所以：

Timestamp 可以比较时间先后，但**不能唯一确定全局执行顺序**。

------

# 4. 企业一般怎么排序？

很多银行项目会这样：

```text
Journal Timestamp

↓

Journal Library

↓

Journal Name

↓

Sequence Number
```

例如：

```text
13:58:10.123

ORDJRN

1003
```

比：

```text
13:58:10.123

CUSJRN

2
```

至少稳定。

但是：

这仍然不是数据库事务真正的 Commit 顺序。

------

# 5. 如果要严格知道事务顺序怎么办？

要看：

```text
Transaction ID
```

例如：

```text
Transaction A

↓

ORDER

↓

CUSTOMER
```

或者：

```text
Commit Cycle
```

IBM CDC 内部其实就是这样保证事务一致性的。

------

# 6. Debezium 为什么喜欢 transaction.id？

你之前问过：

> 为什么 Debezium 有：

```json
"transaction":{
    "id":"..."
}
```

原因就在这里。

例如：

```text
Transaction 100

↓

ORDER_HEADER

↓

ORDER_DETAIL

↓

STOCK

↓

COMMIT
```

它们可能来自：

三个 Journal。

Timestamp 也可能一样。

但是：

```text
transaction.id

=

100
```

于是：

Sink 就知道：

这些属于同一个事务。

------

# 用你现在正在做的项目举例

假设：

```
ORDER_HEADER
```

在：

```text
SALELIB/ORDJRN
CUSTOMER
```

在：

```text
CUSLIB/CUSJRN
```

收到：

```
13:58:10.123
ORDJRN
SEQ=1234
```

以及：

```
13:58:10.125
CUSJRN
SEQ=55
```

我们可以说：

> CUSTOMER 的变更**大概率**发生在 ORDER_HEADER 之后，因为它们共享同一台 IBM i 的系统时钟。

但是如果收到：

```
13:58:10.123456
ORDJRN
SEQ=1234
```

和：

```
13:58:10.123456
CUSJRN
SEQ=55
```

**仅靠时间戳无法断定哪个先发生。**

------

## 最后补充一个很多 IBM i 工程师都会注意的点

**IBM i Journal 本身没有"全局 Sequence Number"。**

所以如果企业需要：

> **整个 AS400 所有 Journal 的绝对顺序**

通常有三种做法：

1. **所有需要 CDC 的 PF 都挂到同一个 Journal**（这是最常见、也是 IBM 官方推荐的配置）。
2. 使用 **IBM CDC 的事务信息（Transaction ID + Commit）** 来恢复事务顺序。
3. 在 Kafka 中增加一个统一的事件编号（例如 CDC 服务生成的全局 Event ID），用于跨 Journal 排序。

这也是为什么**大多数 IBM i 企业会尽量把需要复制的业务库放到同一个 Journal**：这样 `sequence_number` 本身就成为一条严格递增的序列，CDC、恢复和问题排查都会简单得多。

---

利用topic message中source中的数据，同时检查  Journal Sequence 和  Journal Timestamp,做数据断面的判断的话，用kafka streams好实现嘛？