##
 # Copyright (C) 2025 Lectra
 #
 # Licensed under the Apache License, Version 2.0 (the "License");
 # you may not use this file except in compliance with the License.
 # You may obtain a copy of the License at
 #
 #     https://www.apache.org/licenses/LICENSE-2.0
 #
 # Unless required by applicable law or agreed to in writing, software
 # distributed under the License is distributed on an "AS IS" BASIS,
 # WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 # See the License for the specific language governing permissions and
 # limitations under the License.
 #
 # SPDX-License-Identifier: Apache-2.0
 # License-Filename: LICENSE
 ##
@kafka
Feature: Test kafka

  Background:
    * json kafkaConfig = read('classpath:kafka/local-kafka-config.json')
    * def kafkaClient = kafka.topology.createClient(kafkaConfig)

  Scenario: configFromEnv
    When json kafkaConfig = kafka.configFromEnv
    Then match kafkaConfig == { "bootstrap.servers": null, "schema.registry.url": null, "karate.connect.consumer.group.id.prefix": "" }

  Scenario: configSaslFromEnv
    When json kafkaConfig = kafka.configSaslFromEnv
    Then match kafkaConfig == { "bootstrap.servers": null, "schema.registry.url": null, , "karate.connect.consumer.group.id.prefix": "", "security.protocol": null, "sasl.mechanism": null, "sasl.jaas.config": "org.apache.kafka.common.security.scram.ScramLoginModule required username='null' password='null';" }

  Scenario Outline: RegisterSubject <subjectName>
    # config
    * string subjectName = "<subjectName>"
    * string subjectType = "<subjectType>"
    * string schemaString = read('classpath:kafka/<schemaFile>')
    * json subjectConfig = ({ kafkaClient, subjectName, subjectType, schemaString })
    # registering
    * json registerResult = kafka.topology.registerSubject(subjectConfig)
    * match registerResult.status == "OK"
    * match registerResult.schemaId == "#number? _ > 0"

    Examples:
      | subjectName         | subjectType | schemaFile     |
      | my-avro-subject     | AVRO        | avro.avsc      |
      | my-json-subject     | JSON        | schema.json    |
      | my-protobuf-subject | PROTOBUF    | protobuf.proto |

  Scenario: CreateTopic & Producer (Key=String, Value=String, Headers)
    # creating topic
    * json topicConfig = ({ kafkaClient, topic: "mytopic-createtopic-producer", partitions: 1, replicationFactor: 1 })
    * json result = kafka.topology.createTopic(topicConfig)
    * match result.status == "OK"
    # producing
    * json record = ({ key: "myKey", value: "my message", headers: { header1: "foo", header2: "bar" } })
    * json produceResult = kafka.message.produce({...topicConfig, record })
    * match produceResult.status == "OK"
    * match produceResult.recordMetadata.serializedKeySize == "#number? _ > 0"
    * match produceResult.recordMetadata.serializedValueSize == "#number? _ > 0"
    * match produceResult.recordMetadata.topic == topicConfig.topic
    * match produceResult.recordMetadata.partition == 0
    * match produceResult.recordMetadata.timestamp == "#number? _ > 0"
    * match produceResult.recordMetadata.offset == 0

  Scenario: Producer & Consumer By Key
    # config
    * json topicConfig = ({ kafkaClient, topic: "mytopic-producer-consumer-by-key" })
    * kafka.topology.createTopic(topicConfig)
    * json subscribeResult = kafka.message.subscribe(topicConfig)
    * match subscribeResult.status == "OK"
    * json consumer = subscribeResult.consumer
    * def groupIdSplit = consumer.groupId.split("karate-connect-")
    * match groupIdSplit[0] == ""
    * match groupIdSplit[1] == "#uuid"
    * match consumer.topic == "mytopic-producer-consumer-by-key"
    * json consumerByKeyConfig = ({ consumer, key: "myKey1", pollDurationSeconds: 1, timeoutSeconds: 60, maxMessages: 2 })
    # producing
    * json headers = ({ header1: "foo", header2: "bar" })
    * json result1 = kafka.message.produce({...topicConfig, record: { key: "myKey1", value: "my message1", headers } })
    * json result2 = kafka.message.produce({...topicConfig, record: { key: "myKey2", value: "my message2" } })
    * json result3 = kafka.message.produce({...topicConfig, record: { key: "myKey1", value: "my message3" } })
    * json result4 = kafka.message.produce({...topicConfig, record: { key: "myKey1", value: "my message4" } })
    * json statuses = ([ result1.status, result2.status, result3.status, result4.status ])
    * match each statuses == "OK"
    # consuming
    * json result = kafka.message.consumeByKey(consumerByKeyConfig)
    * match result.status == "OK"
    * match (result.data.length) == 2
    * match result.data[0] == { "key":"myKey1", "value":"my message1", "headers":{ "header1":"foo", "header2":"bar" }, "timestamp":"#number? _ > 0", "topic":"mytopic-producer-consumer-by-key", "partition":0,"offset":0 }
    * match result.data[1] == { "key":"myKey1", "value":"my message3", "headers":{}, "timestamp":"#number? _ > 0", "topic":"mytopic-producer-consumer-by-key", "partition":0,"offset":2 }

  Scenario: Producer & Consumer
    # config
    * json topicConfig = ({ kafkaClient, topic: "mytopic-producer-consumer" })
    * kafka.topology.createTopic(topicConfig)
    * json consumer = kafka.message.subscribe(topicConfig).consumer
    * json consumerConfig = ({ consumer, pollDurationSeconds: 1, timeoutSeconds: 60, maxMessages: 2 })
    # producing
    * json headers = ({ header1: "foo", header2: "bar" })
    * json result1 = kafka.message.produce({...topicConfig, record: { key: "myKey1", value: "my message1", headers } })
    * json result2 = kafka.message.produce({...topicConfig, record: { key: "myKey2", value: "my message2" } })
    * json result3 = kafka.message.produce({...topicConfig, record: { key: "myKey1", value: "my message3" } })
    * json result4 = kafka.message.produce({...topicConfig, record: { key: "myKey1", value: "my message4" } })
    * json statuses = ([ result1.status, result2.status, result3.status, result4.status ])
    * match each statuses == "OK"
    # consuming
    * json result = kafka.message.consume(consumerConfig)
    * match result.status == "OK"
    * match (result.data.length) == 2
    * match result.data[0] == { "key":"myKey1", "value":"my message1", "headers":{ "header1":"foo", "header2":"bar" }, "timestamp":"#number? _ > 0", "topic":"mytopic-producer-consumer", "partition":0,"offset":0 }
    * match result.data[1] == { "key":"myKey2", "value":"my message2", "headers":{}, "timestamp":"#number? _ > 0", "topic":"mytopic-producer-consumer", "partition":0,"offset":1 }

  Scenario: Producer & Consumer (Key=AVRO, Value=JSON)
    # registering subjects
    * string keySchemaString = '{ "type": "record", "name": "Key", "fields": [{"name": "foo", "type": "string" }] }'
    * json registerResultKey = kafka.topology.registerSubject({ kafkaClient, subjectName: "my-key-avro-subject", subjectType: "AVRO", schemaString: keySchemaString })
    * string valueSchemaString = '{ "type": "object", "properties": { "bar": {"type": "number"} } }'
    * json registerResultValue = kafka.topology.registerSubject({ kafkaClient, subjectName: "my-value-json-subject", subjectType: "JSON", schemaString: valueSchemaString })
    # creating topic
    * json topicConfig = ({ kafkaClient, topic: "mytopic-producer-consumer-avro-json", partitions: 1, replicationFactor: 1, keySubject: "my-key-avro-subject", valueSubject: "my-value-json-subject" })
    * kafka.topology.createTopic(topicConfig)
    * json consumer = kafka.message.subscribe(topicConfig).consumer
    * json consumerConfig = ({ consumer, pollDurationSeconds: 1, timeoutSeconds: 60, maxMessages: 1, keySubject: "my-key-avro-subject", valueSubject: "my-value-json-subject" })
    # producing
    * json record = ({ key: '{ "foo": "foo1" }' , value: '{ "bar": 42 }' })
    * json produceResult = kafka.message.produce({...topicConfig, record })
    * match produceResult.status == "OK"
    # consuming
    * json result = kafka.message.consume(consumerConfig)
    * match result.status == "OK"
    * match (result.data.length) == 1
    * match result.data[0].key == { "foo": "foo1" }
    * match result.data[0].value == { "bar": 42 }

  Scenario: Producer & Consumer (Key=STRING, Value=PROTOBUF)
    # registering subjects
    * def valueSchemaString = 'syntax = "proto3"; message Value { int32 bar = 1; }'
    * json registerResultValue = kafka.topology.registerSubject({ kafkaClient, subjectName: "my-value-protobuf-subject", subjectType: "PROTOBUF", schemaString: valueSchemaString })
    # creating topic
    * json topicConfig = ({ kafkaClient, topic: "mytopic-producer-consumer-string-protobuf", partitions: 1, replicationFactor: 1, valueSubject: "my-value-protobuf-subject" })
    * kafka.topology.createTopic(topicConfig)
    * json consumer = kafka.message.subscribe(topicConfig).consumer
    * json consumerConfig = ({ consumer, pollDurationSeconds: 1, timeoutSeconds: 60, maxMessages: 1, valueSubject: "my-value-protobuf-subject" })
    # producing
    * json record = ({ key: "foo" , value: '{ "bar": 42 }' })
    * json produceResult = kafka.message.produce({...topicConfig, record })
    * match produceResult.status == "OK"
    # consuming
    * json result = kafka.message.consume(consumerConfig)
    * match result.status == "OK"
    * match (result.data.length) == 1
    * match result.data[0].key == "foo"
    * match result.data[0].value == { "bar": 42 }