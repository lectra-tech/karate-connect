/*
 * Copyright (C) 2025 Lectra
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * SPDX-License-Identifier: Apache-2.0
 * License-Filename: LICENSE
 */
package com.lectra.karate.connect.kafka

import org.apache.kafka.common.errors.TopicExistsException
import org.assertj.core.api.Assertions.assertThat
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows
import java.util.UUID
import java.util.concurrent.ExecutionException

class KafkaClientTest {
    private val localKafkaBroker = LocalKafkaBroker()
    val topic = "topic-unittest"

    @BeforeEach
    fun setUp() {
        localKafkaBroker.start()
        localKafkaBroker.createTopic(topic)
    }

    @AfterEach
    fun tearDown() {
        localKafkaBroker.stop()
    }

    @Test
    fun testRegisterSubject_AVRO() {
        // GIVEN
        val kafkaClient = KafkaClient(bootstrapServers = localKafkaBroker.bootstrapServers(), schemaRegistryUrl = localKafkaBroker.schemaRegistryUrl())
        val schemaString = """
            {
                "type": "record",
                "name": "User",
                "fields": [
                    {"name": "name", "type": "string"},
                    {"name": "age", "type": "int"}
                ]
            }
        """.trimIndent()
        // WHEN
        val schemaId = kafkaClient.registerSubject("subject-avro-unittest", "AVRO", schemaString)
        // THEN
        assertThat(schemaId).isNotNull()
    }

    @Test
    fun testRegisterSubject_JSON() {
        // GIVEN
        val kafkaClient = KafkaClient(bootstrapServers = localKafkaBroker.bootstrapServers(), schemaRegistryUrl = localKafkaBroker.schemaRegistryUrl())
        val schemaString = """
            {
                "type": "object",
                "properties": {
                    "name": {"type": "string"},
                    "age": {"type": "integer"}
                }
            }
        """.trimIndent()
        // WHEN
        val schemaId = kafkaClient.registerSubject("subject-json-unittest", "JSON", schemaString)
        // THEN
        assertThat(schemaId).isNotNull()
    }

    @Test
    fun testRegisterSubject_PROTOBUF() {
        // GIVEN
        val kafkaClient = KafkaClient(bootstrapServers = localKafkaBroker.bootstrapServers(), schemaRegistryUrl = localKafkaBroker.schemaRegistryUrl())
        val schemaString = """
            syntax = "proto3";
            message User {
                string name = 1;
                int32 age = 2;
            }
        """.trimIndent()
        // WHEN
        val schemaId = kafkaClient.registerSubject("subject-protobuf-unittest", "PROTOBUF", schemaString)
        // THEN
        assertThat(schemaId).isNotNull()
    }

    @Test
    fun testCreateTopic() {
        // GIVEN
        val kafkaClient = KafkaClient(localKafkaBroker.bootstrapServers())
        val newTopic = "new-topic-${UUID.randomUUID()}"
        // WHEN
        kafkaClient.createTopic(newTopic, partitions = 1, replicationFactor = 1)
        // THEN
        val allTopics = localKafkaBroker.listTopics()
        assertThat(allTopics).contains(newTopic)
    }

    @Test
    fun testCreateTopicAlreadyExisting() {
        // GIVEN
        val kafkaClient = KafkaClient(localKafkaBroker.bootstrapServers())
        // WHEN
        val exception = assertThrows<ExecutionException> { kafkaClient.createTopic(topic) }
        assertThat { exception.cause is TopicExistsException }
    }

    @Test
    fun testProduce() {
        // GIVEN
        val kafkaClient = KafkaClient(localKafkaBroker.bootstrapServers())
        val key = "test-key"
        val value = "test-value"
        // WHEN
        val result = kafkaClient.produce(topic, key, value)
        // THEN
        assertThat(result).isNotNull()
        assertThat(result.recordMetadata).isNotNull()
        assertThat(result.recordMetadata!!.topic()).isEqualTo(topic)
        assertThat(result.recordMetadata.partition()).isEqualTo(0)
        assertThat(result.recordMetadata.offset()).isEqualTo(0)

        // GIVEN
        val key2 = "test-key2"
        val value2 = null
        val headers = mapOf("header1" to "value1", "header2" to null)
        // WHEN
        val result2 = kafkaClient.produce(topic, key2, value2, headers)
        // THEN
        assertThat(result2).isNotNull()
        assertThat(result2.recordMetadata).isNotNull()
        assertThat(result2.recordMetadata!!.topic()).isEqualTo(topic)
        assertThat(result2.recordMetadata.partition()).isEqualTo(0)
        assertThat(result2.recordMetadata.offset()).isEqualTo(1)
    }

    @Test
    fun testSubscribe() {
        // GIVEN
        val kafkaClient = KafkaClient(localKafkaBroker.bootstrapServers())
        // WHEN
        val consumer = kafkaClient.subscribe(topic)
        // THEN
        assertThat(consumer).isNotNull()
        assertThat(consumer.groupId).isNotNull()
        assertThat(consumer.kafkaConsumer).isNotNull()
        assertThat(consumer.topic).isEqualTo(topic)
        assertThat(consumer.kafkaClient).isEqualTo(kafkaClient)
        assertThat(consumer.partitionOffsets).containsExactly(PartitionOffset(0, 0L))
    }

    @Test
    fun testConsumeByKey() {
        // GIVEN
        val kafkaClient = KafkaClient(localKafkaBroker.bootstrapServers())
        val key = "test-key"
        val badKey = "test-bad-key"
        val value = "test-value"
        val headers = mapOf("header1" to "value1", "header2" to null)
        val consumer = kafkaClient.subscribe(topic)
        kafkaClient.produce(topic, badKey, value, headers)
        // WHEN
        val messages = kafkaClient.consumeByKey(consumer.groupId, topic, key, pollDurationSeconds = 1, timeoutSeconds = 5, maxMessages = 1)
        // THEN
        assertThat(messages).isEmpty()

        // GIVEN
        kafkaClient.produce(topic, key, value, headers)
        // WHEN
        val messages2 = kafkaClient.consumeByKey(consumer.groupId, topic, key, pollDurationSeconds = 1, timeoutSeconds = 5, maxMessages = 1)
        // THEN
        assertThat(messages2).isNotEmpty()
        assertThat(messages2[0].key).isEqualTo(key)
        assertThat(messages2[0].value).isEqualTo(value)
        assertThat(messages2[0].headers).isEqualTo(headers)
        assertThat(messages2[0].topic).isEqualTo(topic)
        assertThat(messages2[0].partition).isEqualTo(0)
        assertThat(messages2[0].offset).isEqualTo(1) // The offset should be 1 since we produced one message before
        assertThat(messages2[0].timestamp).isGreaterThan(0L)
    }

    @Test
    fun testConsume() {
        // GIVEN
        val kafkaClient = KafkaClient(localKafkaBroker.bootstrapServers())
        val key = "test-key"
        val value = "test-value"
        val key2 = "test-key2"
        val value2 = "test-value2"
        val key3 = null
        val value3 = "test-value3"
        val consumer = kafkaClient.subscribe(topic)
        kafkaClient.produce(topic, key, value)
        kafkaClient.produce(topic, key2, value2)
        kafkaClient.produce(topic, key3, value3)
        // WHEN
        val messages = kafkaClient.consume(consumer.groupId, topic, pollDurationSeconds = 2, timeoutSeconds = 5, maxMessages = 3)
        // THEN
        assertThat(messages).hasSize(3)
        assertThat(messages[0].value).isEqualTo(value)
        assertThat(messages[1].value).isEqualTo(value2)
        assertThat(messages[2].value).isEqualTo(value3)
    }

    @Test
    fun testProduceConsumeAVRO() {
        // GIVEN
        val kafkaClient = KafkaClient(localKafkaBroker.bootstrapServers(), schemaRegistryUrl = localKafkaBroker.schemaRegistryUrl())
        kafkaClient.registerSubject("my-key-avro-subject-unittest", "AVRO", """{ "type": "record", "name": "Key", "fields": [{"name": "foo", "type": "string" }] }""")
        kafkaClient.registerSubject("my-value-avro-subject-unittest", "AVRO", """{ "type": "record", "name": "Value", "fields": [{"name": "bar", "type": "int" }] }""")
        val key = """{"foo":"foo1"}"""
        val value = """{"bar":42}"""
        val consumer = kafkaClient.subscribe(topic)
        // WHEN
        val produceResult = kafkaClient.produce(topic, key, value, keySubject = "my-key-avro-subject-unittest", valueSubject = "my-value-avro-subject-unittest")
        val messages = kafkaClient.consume(consumer.groupId, topic, pollDurationSeconds = 2, timeoutSeconds = 5, maxMessages = 1, keySubject = "my-key-avro-subject-unittest", valueSubject = "my-value-avro-subject-unittest")
        // THEN
        assertThat(produceResult).isNotNull()
        assertThat(produceResult.recordMetadata).isNotNull()
        assertThat(messages).hasSize(1)
        assertThat(messages[0].key).isEqualTo(key)
        assertThat(messages[0].value).isEqualTo(value)
    }

    @Test
    fun testProduceConsumeJSON() {
        // GIVEN
        val kafkaClient = KafkaClient(localKafkaBroker.bootstrapServers(), schemaRegistryUrl = localKafkaBroker.schemaRegistryUrl())
        kafkaClient.registerSubject("my-key-json-subject-unittest", "JSON", """{ "type": "object", "properties": { "foo": {"type": "string"} } }""")
        kafkaClient.registerSubject("my-value-json-subject-unittest", "JSON", """{ "type": "object", "properties": { "bar": {"type": "number"} } }""")
        val key = """{"foo":"foo1"}"""
        val value = """{"bar":42}"""
        val consumer = kafkaClient.subscribe(topic)
        // WHEN
        val produceResult = kafkaClient.produce(topic, key, value, keySubject = "my-key-json-subject-unittest", valueSubject = "my-value-json-subject-unittest")
        val messages = kafkaClient.consume(consumer.groupId, topic, pollDurationSeconds = 2, timeoutSeconds = 5, maxMessages = 1, keySubject = "my-key-json-subject-unittest", valueSubject = "my-value-json-subject-unittest")
        // THEN
        assertThat(produceResult).isNotNull()
        assertThat(produceResult.recordMetadata).isNotNull()
        assertThat(messages).hasSize(1)
        assertThat(messages[0].key).isEqualTo(key)
        assertThat(messages[0].value).isEqualTo(value)
    }

    @Test
    fun testProduceConsumePROTOBUF() {
        // GIVEN
        val kafkaClient = KafkaClient(localKafkaBroker.bootstrapServers(), schemaRegistryUrl = localKafkaBroker.schemaRegistryUrl())
        kafkaClient.registerSubject("my-key-protobuf-subject-unittest", "PROTOBUF", """syntax = "proto3"; message Key { string foo = 1; }""")
        kafkaClient.registerSubject("my-value-protobuf-subject-unittest", "PROTOBUF", """syntax = "proto3"; message Value { int32 bar = 1; }""")
        val key = """{"foo":"foo1"}"""
        val value = """{"bar":42}"""
        val consumer = kafkaClient.subscribe(topic)
        // WHEN
        val produceResult = kafkaClient.produce(topic, key, value, keySubject = "my-key-protobuf-subject-unittest", valueSubject = "my-value-protobuf-subject-unittest")
        val messages = kafkaClient.consume(consumer.groupId, topic, pollDurationSeconds = 2, timeoutSeconds = 5, maxMessages = 1, keySubject = "my-key-protobuf-subject-unittest", valueSubject = "my-value-protobuf-subject-unittest")
        // THEN
        assertThat(produceResult).isNotNull()
        assertThat(produceResult.recordMetadata).isNotNull()
        assertThat(messages).hasSize(1)
        assertThat(messages[0].key).isEqualTo(key)
        assertThat(messages[0].value).isEqualTo(value)
    }
}