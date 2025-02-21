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

  @publish
  Scenario: publish
  args: { rabbitmqClient: ..., exchangeName: "...", routingKey: "...", message: { body : "...", properties: { headers, ... } } }
    * rabbitmqClient.publish(exchangeName, routingKey, rabbitmq.Message.from(message.body, message.properties))
    * json result = { status: "OK" }

  @consume
  Scenario: consume
  args: { rabbitmqClient: ..., queueName: "...", timeoutSeconds: ..., minNbMessages: ...  }
    * def timeoutSecondsValue = karate.get("timeoutSeconds", 60)
    * def minNbMessagesValue = karate.get("minNbMessages", 1)
    * def messages = rabbitmqClient.consume(queueName, timeoutSecondsValue, minNbMessagesValue)
    * json data = karate.map(messages, (message) => message.toMap())
    * json result = ({ status: "OK", data })

  @publishAndConsume
  Scenario: publishAndConsume
  args: { rabbitmqClient: ..., exchangeName: "...", routingKey: "...", message: { body : "...", properties: { headers, ... } }, timeoutSeconds: ... }
    * def timeoutSecondsValue = karate.get("timeoutSeconds", 60)
    * def message = rabbitmqClient.publishAndConsume(exchangeName, routingKey, rabbitmq.Message.from(message.body, message.properties), timeoutSecondsValue)
    * json data = message.toMap()
    * json result = ({ status: "OK", data })
