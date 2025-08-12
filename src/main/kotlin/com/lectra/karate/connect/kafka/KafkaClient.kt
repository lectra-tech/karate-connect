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

import com.fasterxml.jackson.core.JsonProcessingException
import com.fasterxml.jackson.core.type.TypeReference
import com.fasterxml.jackson.databind.JsonMappingException
import com.fasterxml.jackson.databind.JsonNode
import com.google.protobuf.Message
import com.lectra.karate.connect.BrokerClient
import io.confluent.kafka.schemaregistry.avro.AvroSchema
import io.confluent.kafka.schemaregistry.avro.AvroSchemaProvider
import io.confluent.kafka.schemaregistry.avro.AvroSchemaUtils
import io.confluent.kafka.schemaregistry.client.SchemaRegistryClientConfig
import io.confluent.kafka.schemaregistry.client.SchemaRegistryClientFactory
import io.confluent.kafka.schemaregistry.json.JsonSchema
import io.confluent.kafka.schemaregistry.json.JsonSchemaProvider
import io.confluent.kafka.schemaregistry.json.JsonSchemaUtils
import io.confluent.kafka.schemaregistry.json.jackson.Jackson
import io.confluent.kafka.schemaregistry.protobuf.ProtobufSchema
import io.confluent.kafka.schemaregistry.protobuf.ProtobufSchemaProvider
import io.confluent.kafka.schemaregistry.protobuf.ProtobufSchemaUtils
import io.confluent.kafka.serializers.AbstractKafkaSchemaSerDeConfig
import io.confluent.kafka.serializers.KafkaAvroDeserializer
import io.confluent.kafka.serializers.KafkaAvroDeserializerConfig
import io.confluent.kafka.serializers.KafkaAvroSerializer
import io.confluent.kafka.serializers.json.KafkaJsonSchemaDeserializer
import io.confluent.kafka.serializers.json.KafkaJsonSchemaDeserializerConfig
import io.confluent.kafka.serializers.json.KafkaJsonSchemaSerializer
import io.confluent.kafka.serializers.json.KafkaJsonSchemaSerializerConfig
import io.confluent.kafka.serializers.protobuf.KafkaProtobufDeserializer
import io.confluent.kafka.serializers.protobuf.KafkaProtobufSerializer
import org.apache.kafka.clients.CommonClientConfigs
import org.apache.kafka.clients.admin.AdminClient
import org.apache.kafka.clients.admin.NewTopic
import org.apache.kafka.clients.consumer.ConsumerConfig
import org.apache.kafka.clients.consumer.KafkaConsumer
import org.apache.kafka.clients.producer.*
import org.apache.kafka.common.TopicPartition
import org.apache.kafka.common.config.SaslConfigs
import org.apache.kafka.common.header.internals.RecordHeader
import org.apache.kafka.common.serialization.ByteArrayDeserializer
import org.apache.kafka.common.serialization.ByteArraySerializer
import org.slf4j.Logger
import java.time.Duration
import java.util.*
import java.util.concurrent.ConcurrentHashMap
import kotlin.time.Duration.Companion.seconds
import kotlin.time.TimeSource


class KafkaClient(
    private val bootstrapServers: String,
    // security
    private val securityProtocol: String? = null,
    private val saslMechanism: String? = null,
    private val saslJaasConfig: String? = null,
    // schema registry
    private val schemaRegistryUrl: String? = null,
    private val basicAuthCredentialsSource: String? = null,
    private val basicAuthUserInfo: String? = null,
    // groupId
    private val consumerGroupIdPrefix: String? = null

) : BrokerClient() {

    private val brokerMap = mutableMapOf<String, String>().apply {
        put(CommonClientConfigs.BOOTSTRAP_SERVERS_CONFIG, bootstrapServers)
        securityProtocol?.let { put(CommonClientConfigs.SECURITY_PROTOCOL_CONFIG, it) }
        saslMechanism?.let { put(SaslConfigs.SASL_MECHANISM, it) }
        saslJaasConfig?.let { put(SaslConfigs.SASL_JAAS_CONFIG, it) }
    }.toMap()

    private val consumers = ConcurrentHashMap<String, Consumer>()
    private val adminClient = AdminClient.create(brokerMap)

    private val schemaRegistryClient =
        schemaRegistryUrl?.let { url ->
            val configs = basicAuthCredentialsSource?.let { source ->
                if (source == "USER_INFO") {
                    val userInfo = basicAuthUserInfo
                        ?: throw IllegalArgumentException("Basic Auth User Info must be provided when using USER_INFO source")
                    mapOf(
                        SchemaRegistryClientConfig.BASIC_AUTH_CREDENTIALS_SOURCE to source,
                        SchemaRegistryClientConfig.USER_INFO_CONFIG to userInfo
                    )
                } else emptyMap()
            } ?: emptyMap()
            SchemaRegistryClientFactory.newClient(
                url,
                AbstractKafkaSchemaSerDeConfig.MAX_SCHEMAS_PER_SUBJECT_DEFAULT,
                listOf(AvroSchemaProvider(), JsonSchemaProvider(), ProtobufSchemaProvider()),
                configs,
                emptyMap()
            )
        }

    // AVRO
    private val avroSerializerConfig = mapOf(
        AbstractKafkaSchemaSerDeConfig.SCHEMA_REGISTRY_URL_CONFIG to schemaRegistryUrl,
        AbstractKafkaSchemaSerDeConfig.AUTO_REGISTER_SCHEMAS to "true"
    )
    private val avroKeySerializer = schemaRegistryClient?.let { client ->
        val result = KafkaAvroSerializer(client)
        result.configure(avroSerializerConfig, true)
        result
    }
    private val avroValueSerializer = schemaRegistryClient?.let { client ->
        val result = KafkaAvroSerializer(client)
        result.configure(avroSerializerConfig, false)
        result
    }
    private val avroDeserializerConfig = mapOf(
        AbstractKafkaSchemaSerDeConfig.SCHEMA_REGISTRY_URL_CONFIG to schemaRegistryUrl,
        KafkaAvroDeserializerConfig.SPECIFIC_AVRO_READER_CONFIG to "false"
    )
    private val avroKeyDeserializer = schemaRegistryClient?.let { client ->
        val result = KafkaAvroDeserializer(client)
        result.configure(avroDeserializerConfig, true)
        result
    }
    private val avroValueDeserializer = schemaRegistryClient?.let { client ->
        val result = KafkaAvroDeserializer(client)
        result.configure(avroDeserializerConfig, false)
        result
    }

    // JSON
    val objectMapper = Jackson.newObjectMapper();
    private val jsonSerializerConfig = mapOf(
        AbstractKafkaSchemaSerDeConfig.SCHEMA_REGISTRY_URL_CONFIG to schemaRegistryUrl,
        AbstractKafkaSchemaSerDeConfig.AUTO_REGISTER_SCHEMAS to "true",
        KafkaJsonSchemaSerializerConfig.FAIL_INVALID_SCHEMA to "true"
    )
    private val jsonKeySerializer = schemaRegistryClient?.let { client ->
        val result = KafkaJsonSchemaSerializer<JsonNode>(client, jsonSerializerConfig)
        result.configure(jsonSerializerConfig, true)
        result
    }
    private val jsonValueSerializer = schemaRegistryClient?.let { client ->
        val result = KafkaJsonSchemaSerializer<JsonNode>(client, jsonSerializerConfig)
        result.configure(jsonSerializerConfig, false)
        result
    }
    private val jsonDeserializerConfig = mapOf(
        AbstractKafkaSchemaSerDeConfig.SCHEMA_REGISTRY_URL_CONFIG to schemaRegistryUrl,
        KafkaJsonSchemaDeserializerConfig.JSON_KEY_TYPE to JsonNode::class.java.name,
        KafkaJsonSchemaDeserializerConfig.JSON_VALUE_TYPE to JsonNode::class.java.name
    )
    private val jsonKeyDeserializer = schemaRegistryClient?.let { client ->
        val result = KafkaJsonSchemaDeserializer<JsonNode>(client)
        result.configure(jsonDeserializerConfig, true)
        result
    }
    private val jsonValueDeserializer = schemaRegistryClient?.let { client ->
        val result = KafkaJsonSchemaDeserializer<JsonNode>(client)
        result.configure(jsonDeserializerConfig, false)
        result
    }

    // PROTOBUF
    private val protobufSerializerConfig = mapOf(
        AbstractKafkaSchemaSerDeConfig.SCHEMA_REGISTRY_URL_CONFIG to schemaRegistryUrl,
        AbstractKafkaSchemaSerDeConfig.AUTO_REGISTER_SCHEMAS to "true"
    )
    private val protobufKeySerializer = schemaRegistryClient?.let { client ->
        val result = KafkaProtobufSerializer<Message>(client, protobufSerializerConfig)
        result.configure(protobufSerializerConfig, true)
        result
    }
    private val protobufValueSerializer = schemaRegistryClient?.let { client ->
        val result = KafkaProtobufSerializer<Message>(client, protobufSerializerConfig)
        result.configure(protobufSerializerConfig, false)
        result
    }
    private val protobufDeserializerConfig = mapOf(
        AbstractKafkaSchemaSerDeConfig.SCHEMA_REGISTRY_URL_CONFIG to schemaRegistryUrl
    )
    private val protobufKeyDeserializer = schemaRegistryClient?.let { client ->
        val result = KafkaProtobufDeserializer<Message>(client)
        result.configure(protobufDeserializerConfig, true)
        result
    }
    private val protobufValueDeserializer = schemaRegistryClient?.let { client ->
        val result = KafkaProtobufDeserializer<Message>(client)
        result.configure(protobufDeserializerConfig, false)
        result
    }

    override fun close() {
        logExecution("Closing consumers") {
            consumers.forEach { (_, consumer) ->
                consumer.kafkaConsumer.unsubscribe()
                consumer.kafkaConsumer.close()
            }
            adminClient.deleteConsumerGroups(consumers.keys().toList())
        }
        adminClient.close()
    }

    fun registerSubject(subjectName: String, subjectType: String, schemaString: String): Int {
        return logExecution("Registering schema for subject '$subjectName'") {
            val schemaClient = schemaRegistryClient
                ?: throw IllegalStateException("Schema Registry URL not configured")

            when (subjectType) {
                "AVRO" -> schemaClient.register(subjectName, AvroSchema(schemaString))
                "JSON" -> schemaClient.register(subjectName, JsonSchema(schemaString))
                "PROTOBUF" -> schemaClient.register(subjectName, ProtobufSchema(schemaString))
                else -> throw IllegalArgumentException("Unsupported subject type: $subjectType")
            }
        }
    }

    fun createTopic(topic: String, partitions: Int = 1, replicationFactor: Short = 1) {
        return logExecution("Creating topic '$topic' with $partitions partitions and replication factor $replicationFactor") {
            val newTopic = NewTopic(topic, partitions, replicationFactor)
            adminClient.createTopics(listOf(newTopic)).all().get()
        }
    }

    private fun serializeWithSchema(
        data: String?,
        subject: String?,
        topic: String,
        isKey: Boolean
    ): ByteArray? {
        return subject?.let { subjectName ->
            schemaRegistryClient?.getLatestSchemaMetadata(subjectName)?.let { schemaMetadata ->
                data?.let {
                    when (schemaMetadata.schemaType) {
                        "AVRO" -> {
                            val schema = AvroSchema(schemaMetadata.schema)
                            val record = AvroSchemaUtils.toObject(it, schema)
                            if (isKey) avroKeySerializer?.serialize(topic, record)
                            else avroValueSerializer?.serialize(topic, record)
                        }

                        "JSON" -> {
                            val schema = JsonSchema(schemaMetadata.schema)
                            val payloadJsonNode = objectMapper.readTree(it)
                            val record = JsonSchemaUtils.envelope(schema, payloadJsonNode)
                            if (isKey) jsonKeySerializer?.serialize(topic, record)
                            else jsonValueSerializer?.serialize(topic, record)
                        }

                        "PROTOBUF" -> {
                            val schema = ProtobufSchema(schemaMetadata.schema)
                            val payloadJsonNode = objectMapper.readTree(it)
                            val record: Message = ProtobufSchemaUtils.toObject(payloadJsonNode, schema) as Message
                            if (isKey) protobufKeySerializer?.serialize(topic, record)
                            else protobufValueSerializer?.serialize(topic, record)
                        }

                        else -> throw IllegalArgumentException("Unsupported subject type: ${schemaMetadata.schemaType}")
                    }
                }
            }
        } ?: data?.toByteArray()
    }

    private fun deserializeWithSchema(data: ByteArray?, subject: String, isKey: Boolean): String? {
        return data?.let { byteArray ->
            schemaRegistryClient?.getLatestSchemaMetadata(subject)?.let { schemaMetadata ->
                when (schemaMetadata.schemaType) {
                    "AVRO" -> {
                        val record =
                            if (isKey) avroKeyDeserializer?.deserialize(subject, byteArray)
                            else avroValueDeserializer?.deserialize(subject, byteArray)
                        record?.let { String(AvroSchemaUtils.toJson(record)) }
                    }

                    "JSON" -> {
                        val record =
                            if (isKey) jsonKeyDeserializer?.deserialize(subject, byteArray)
                            else jsonValueDeserializer?.deserialize(subject, byteArray)
                        record?.toString()
                    }

                    "PROTOBUF" -> {
                        val record =
                            if (isKey) protobufKeyDeserializer?.deserialize(subject, byteArray)
                            else protobufValueDeserializer?.deserialize(subject, byteArray)
                        record?.let { String(ProtobufSchemaUtils.toJson(record)) }
                    }

                    else -> throw IllegalArgumentException("Unsupported subject type: ${schemaMetadata.schemaType}")
                }
            } ?: String(byteArray)
        }

    }

    fun produce(
        topic: String,
        key: String?,
        value: String?,
        headers: Map<String, String?> = emptyMap(),
        keySubject: String? = null,
        valueSubject: String? = null
    ): ProduceResult {
        return logExecution("Producing message to topic '$topic' with key '$key'") {
            val keyByteArray = serializeWithSchema(key, keySubject, topic, isKey = true)
            val valueByteArray = serializeWithSchema(value, valueSubject, topic, isKey = false)
            val producerProperties = Properties()
            brokerMap.forEach { (key, value) -> producerProperties[key] = value }
            producerProperties[ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG] = ByteArraySerializer::class.java
            producerProperties[ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG] = ByteArraySerializer::class.java
            producerProperties[ProducerConfig.ACKS_CONFIG] = "1"
            val producer: Producer<ByteArray?, ByteArray?> = KafkaProducer<ByteArray?, ByteArray?>(producerProperties)
            val callback = Callback { recordMetadata, e ->
                LOGGER.info("topic: ${recordMetadata.topic()}, partition: ${recordMetadata.partition()}, offset: ${recordMetadata.offset()}")
            }
            val kafkaHeaders = headers.map { RecordHeader(it.key, it.value?.toByteArray()) }
            val recordMetadata: RecordMetadata? = producer.send(
                ProducerRecord(topic, null, keyByteArray, valueByteArray, kafkaHeaders),
                callback
            ).get()
            producer.flush()
            producer.close()
            ProduceResult(recordMetadata)
        }
    }

    fun subscribe(topic: String): Consumer {
        return logExecution("Subscribing to topic '$topic'") {
            val consumerProperties = Properties()
            brokerMap.forEach { (key, value) -> consumerProperties[key] = value }
            consumerProperties[ConsumerConfig.KEY_DESERIALIZER_CLASS_CONFIG] =
                ByteArrayDeserializer::class.java.getName()
            consumerProperties[ConsumerConfig.VALUE_DESERIALIZER_CLASS_CONFIG] =
                ByteArrayDeserializer::class.java.getName()
            val consumerGroupId = "${consumerGroupIdPrefix?:""}${UUID.randomUUID()}"
            consumerProperties[ConsumerConfig.GROUP_ID_CONFIG] = consumerGroupId
            consumerProperties[ConsumerConfig.AUTO_OFFSET_RESET_CONFIG] = "latest"
            consumerProperties[ConsumerConfig.ENABLE_AUTO_COMMIT_CONFIG] = true
            consumerProperties[ConsumerConfig.ISOLATION_LEVEL_CONFIG] = "read_committed"

            val kafkaConsumer = KafkaConsumer<ByteArray?, ByteArray?>(consumerProperties)
            kafkaConsumer.assign(kafkaConsumer.partitionsFor(topic).map { TopicPartition(it.topic(), it.partition()) })
            val partitionOffsets =
                kafkaConsumer.assignment().map { PartitionOffset(it.partition(), kafkaConsumer.position(it)) }
            kafkaConsumer.commitSync()
            val result = Consumer(this, kafkaConsumer, topic, consumerGroupId, partitionOffsets)
            consumers.put(consumerGroupId, result)
            LOGGER.info(result.toString())
            result
        }
    }

    private fun consumeMessages(
        consumerGroupId: String, topic: String, predicateOnKey: ((key: ByteArray?) -> Boolean)? = null,
        pollDurationSeconds: Long = 1, timeoutSeconds: Long = 60, maxMessages: Long = 100,
        keySubject: String? = null, valueSubject: String? = null
    ): List<Record> {
        val logMessage = predicateOnKey?.let { "Consuming filtered messages from topic '$topic'" }
            ?: "Consuming all messages from topic '$topic'"
        return logExecution(logMessage) {
            val consumer = consumers[consumerGroupId]
                ?: throw IllegalStateException("Consumer with group ID '$consumerGroupId' not found")
            val kafkaConsumer = consumer.kafkaConsumer
            val stopTime = TimeSource.Monotonic.markNow() + timeoutSeconds.seconds
            val records = mutableListOf<Record>()
            while (stopTime.hasNotPassedNow() && records.size < maxMessages) {
                val polledRecords = kafkaConsumer.poll(Duration.ofSeconds(pollDurationSeconds)).records(topic)
                val filteredRecords =
                    predicateOnKey?.let { polledRecords.filter { record -> it(record.key()) } }
                        ?: polledRecords
                records.addAll(filteredRecords.map {
                    Record(
                        key = it.key()?.let { key ->
                            keySubject?.let { subject -> deserializeWithSchema(key, subject, isKey = true) } ?: String(
                                key
                            )
                        },
                        value = it.value()?.let { value ->
                            valueSubject?.let { subject -> deserializeWithSchema(value, subject, isKey = false) }
                                ?: String(value)
                        },
                        topic = it.topic(),
                        partition = it.partition(),
                        offset = it.offset(),
                        headers = it.headers().associate { header ->
                            header.key() to header.value()?.let { headerValue -> String(headerValue) }
                        },
                        timestamp = it.timestamp()
                    )
                })
            }
            kafkaConsumer.commitSync()
            records.take(maxMessages.toInt())
        }
    }

    // Convenience methods for common use cases
    fun consume(
        consumerGroupId: String, topic: String,
        pollDurationSeconds: Long = 1,
        timeoutSeconds: Long = 60,
        maxMessages: Long = 100,
        keySubject: String? = null,
        valueSubject: String? = null
    ): List<Record> = consumeMessages(
        consumerGroupId,
        topic,
        null,
        pollDurationSeconds,
        timeoutSeconds,
        maxMessages,
        keySubject,
        valueSubject
    )

    fun consumeByKey(
        consumerGroupId: String,
        topic: String,
        key: String? = null,
        pollDurationSeconds: Long = 1,
        timeoutSeconds: Long = 60,
        maxMessages: Long = 100,
        keySubject: String? = null,
        valueSubject: String? = null
    ): List<Record> = consumeMessages(
        consumerGroupId,
        topic,
        { recordKey ->
            (recordKey?.let { String(it) == key } ?: (key == null))
        }, // TODO test if key is Avro/JSON/Protobuf
        pollDurationSeconds,
        timeoutSeconds,
        maxMessages,
        keySubject,
        valueSubject
    )

}

data class ProduceResult(
    val recordMetadata: RecordMetadata?
) {
    fun toMap(): Map<String, Any?> {
        return recordMetadata?.let { it ->
            mapOf(
                "timestamp" to it.timestamp(),
                "offset" to it.offset(),
                "serializedKeySize" to it.serializedKeySize(),
                "serializedValueSize" to it.serializedValueSize(),
                "topic" to it.topic(),
                "partition" to it.partition()
            )
        } ?: emptyMap()
    }
}

data class Record(
    val key: String?,
    val value: String?,
    val headers: Map<String, String?> = emptyMap(),
    val timestamp: Long,
    val topic: String,
    val partition: Int,
    val offset: Long
) {
    override fun toString(): String {
        return "Record(key=$key, value=$value, headers=$headers, timestamp=$timestamp), topic='$topic', partition=$partition, offset=$offset"
    }

    private fun parseJson(kafkaClient: KafkaClient, stringValue: String) : Any? {
        return try {
            kafkaClient.objectMapper.readValue(stringValue, object : TypeReference<Map<String?, Any?>?>() {})
        } catch (e: JsonProcessingException) {
            kafkaClient.LOGGER.error(e.message, e)
            stringValue
        } catch (e: JsonMappingException) {
            kafkaClient.LOGGER.error(e.message, e)
            stringValue
        }
    }

    fun toMap(kafkaClient: KafkaClient, keySubject: String?, valueSubject: String?): Map<String, Any?> {
        return mapOf(
            "key" to (keySubject?.let { key?.let { parseJson(kafkaClient, it) } } ?: key),
            "value" to (valueSubject?.let { value?.let { parseJson(kafkaClient, it) } } ?: value),
            "headers" to headers,
            "timestamp" to timestamp,
            "topic" to topic,
            "partition" to partition,
            "offset" to offset
        )
    }
}

data class Consumer(
    val kafkaClient: KafkaClient,
    val kafkaConsumer: KafkaConsumer<ByteArray?, ByteArray?>,
    val topic: String,
    val groupId: String,
    val partitionOffsets: List<PartitionOffset>
) {
    override fun toString(): String {
        return "Consumer(topic='$topic', groupId='$groupId', partitionOffsets=$partitionOffsets)"
    }

    fun toMap(): Map<String, Any> {
        return mapOf(
            "kafkaClient" to kafkaClient,
            "topic" to topic,
            "groupId" to groupId,
            "partitionOffsets" to partitionOffsets.map { mapOf("partition" to it.partition, "offset" to it.offset) }
        )
    }
}

data class PartitionOffset(
    val partition: Int,
    val offset: Long
)
