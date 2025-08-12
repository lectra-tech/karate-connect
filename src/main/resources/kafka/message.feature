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
Feature: message

  @produce
  Scenario: produce
  args: { kafkaClient: ..., topic: "...", keySubject: "...", valueSubject: "...", record: { key : "...", value: "...", headers:  { ... } } }
    * def headers = karate.get("record.headers", {})
    * def keySubjectValue = karate.get("keySubject")
    * def valueSubjectValue = karate.get("valueSubject")
    * def produceResult = kafkaClient.produce(topic, record.key, record.value, headers, keySubjectValue, valueSubjectValue)
    * json recordMetadata = produceResult.toMap()
    * json result = ({ status: "OK", recordMetadata })

  @subscribe
  Scenario: subscribe
  args: { kafkaClient: ..., topic: "..." }
    * def consumer = kafkaClient.subscribe(topic)
    * json consumerJson = consumer.toMap()
    * json result = ({ status: "OK", consumer: consumerJson })

  @consumeByKey
  Scenario: consumeByKey
  args: { consumer: {...}, key: "...", pollDurationSeconds: ..., timeoutSeconds: ..., maxMessages: ..., keySubject: "...", valueSubject: "..." }
    * def pollDurationSecondsValue = karate.get("pollDurationSeconds", 1)
    * def timeoutSecondsValue = karate.get("timeoutSeconds", 60)
    * def maxMessagesValue = karate.get("maxMessages", 100)
    * def keySubjectValue = karate.get("keySubject")
    * def valueSubjectValue = karate.get("valueSubject")
    * def records = consumer.kafkaClient.consumeByKey(consumer.groupId, consumer.topic, key, pollDurationSecondsValue, timeoutSecondsValue, maxMessagesValue, keySubjectValue, valueSubjectValue)
    * json data = karate.map(records, (record) => record.toMap(consumer.kafkaClient, keySubjectValue, valueSubjectValue))
    * json result = ({ status: "OK", data })

  @consume
  Scenario: consume
  args: { consumer: {...}, pollDurationSeconds: ..., timeoutSeconds: ..., maxMessages: ..., keySubject: "...", valueSubject: "..." }
    * def pollDurationSecondsValue = karate.get("pollDurationSeconds", 1)
    * def timeoutSecondsValue = karate.get("timeoutSeconds", 60)
    * def maxMessagesValue = karate.get("maxMessages", 100)
    * def keySubjectValue = karate.get("keySubject")
    * def valueSubjectValue = karate.get("valueSubject")
    * def records = consumer.kafkaClient.consume(consumer.groupId, consumer.topic, pollDurationSecondsValue, timeoutSecondsValue, maxMessagesValue, keySubjectValue, valueSubjectValue)
    * json data = karate.map(records, (record) => record.toMap(consumer.kafkaClient, keySubjectValue, valueSubjectValue))
    * json result = ({ status: "OK", data })