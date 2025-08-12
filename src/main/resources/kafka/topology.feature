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
@ignore
Feature: topology

  @createClient
  Scenario: createClient
  args = { "bootstrap.servers": "xxx:9092",
           "schema.registry.url": "http://xxx:8081", "basic.auth.credentials.source": "USER_INFO", "basic.auth.user.info": "key:secret",
           "security.protocol": "SASL_SSL", "sasl.mechanism": "PLAIN",
           "sasl.jaas.config": "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"user\" password=\"password\";",
           "karate.connect.consumer.group.id.prefix": "test-group-" } }
    * string bootstrapServers = karate.get("bootstrap.servers")
    * string securityProtocol = karate.get("security.protocol", null)
    * string saslMechanism = karate.get("sasl.mechanism", null)
    * string saslJaasConfig = karate.get("sasl.jaas.config", null)
    * string schemaRegistryUrl = karate.get("schema.registry.url", null)
    * string basicAuthCredentialsSource = karate.get("basic.auth.credentials.source", null)
    * string basicAuthUserInfo = karate.get("basic.auth.user.info", null)
    * string consumerGroupIdPrefix = karate.get("karate.connect.consumer.group.id.prefix", null)
    * def result = new kafka.KafkaClient(bootstrapServers, securityProtocol, saslMechanism, saslJaasConfig, schemaRegistryUrl, basicAuthCredentialsSource, basicAuthUserInfo, consumerGroupIdPrefix)
    * match result.getClass().getName() == "com.lectra.karate.connect.kafka.KafkaClient"

  @createTopic
  Scenario: createTopic
  args = { kafkaClient: ..., topic: "mytopic", partitions: 1, replicationFactor: 1 }
    * def partitionsValue = karate.get("partitions", 1)
    * def replicationFactorValue = karate.get("replicationFactor", 1)
    * kafkaClient.createTopic(topic, partitionsValue, replicationFactorValue)
    * json result = ({ status: "OK" })

  @registerSubject
  Scenario: registerSubject
  args = { kafkaClient: ..., subjectName: "my-subject", subjectType: "AVRO|JSON|PROTOBUF", schemaString: "..." }
    * def schemaId = kafkaClient.registerSubject(subjectName, subjectType, schemaString)
    * json result = ({ status: "OK", schemaId: schemaId })
