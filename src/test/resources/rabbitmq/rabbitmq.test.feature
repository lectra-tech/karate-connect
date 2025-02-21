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
@rabbitmq
Feature: Test rabbitmq

  Background:
    * json rabbitmqConfig = read('classpath:rabbitmq/local-rabbitmq-config.json')
    * def rabbitmqClient = rabbitmq.topology.createClient(rabbitmqConfig)

  Scenario: NoMessage
  emptyqueue <= consumer ... nothing
    # config
    * json emptyQueueConfig = ({ rabbitmqClient, name: "myemptyqueue", type: "classic", durable: true, exclusive: false, autoDelete: false })
    * json consumeEmptyConfig = ({ rabbitmqClient, queueName: emptyQueueConfig.name, timeoutSeconds: 5, minNbMessages: 0 })
    # queue
    * json result = rabbitmq.topology.queue(emptyQueueConfig)
    * match result.status == "OK"
    # consuming
    * json result = rabbitmq.message.consume(consumeEmptyConfig)
    * match result.status == "OK"
    * match result.data == []

  Scenario: Nominal
  producer ✉️ => exchange --routingKey--> queue <= consumer ✉️
    # config
    * json exchangeConfig = ({ rabbitmqClient, name: "myexchange", type: "topic", durable: true, autoDelete: false })
    * json queueConfig = ({ rabbitmqClient, name: "myqueue", type: "classic", durable: true, exclusive: false, autoDelete: false })
    * json bindingConfig = ({ rabbitmqClient, exchangeName: exchangeConfig.name, queueName: queueConfig.name, routingKey: "my.routing.key" })
    * json publishConfig = ({ rabbitmqClient, exchangeName: exchangeConfig.name, routingKey: bindingConfig.routingKey })
    * json consumeConfig = ({ rabbitmqClient, queueName: queueConfig.name, timeoutSeconds: 240, minNbMessages: 2 })
    * json headers = { header1: "foo", header2: "bar" }
    * json properties = ({ headers, contentType: "application/json" })
    # exchange
    * json result = rabbitmq.topology.exchange(exchangeConfig)
    * match result.status == "OK"
    # queue
    * json result = rabbitmq.topology.queue(queueConfig)
    * match result.status == "OK"
    # binding
    * json result = rabbitmq.topology.bind(bindingConfig)
    * match result.status == "OK"
    # producing
    * json input1 = ({ body: "my message 1", properties: properties })
    * json input2 = ({ body: "my message 2", properties: properties })
    * json result = rabbitmq.message.publish({...publishConfig, message: input1})
    * json result = rabbitmq.message.publish({...publishConfig, message: input2})
    * match result.status == "OK"
    # consuming
    * json result = rabbitmq.message.consume(consumeConfig)
    * match result.status == "OK"
    * match result.data[0].body == input1.body
    * match result.data[0].properties contains input1.properties
    * match result.data[1].body == input2.body
    * match result.data[1].properties contains input2.properties

  Scenario: RPC
  producer ✉️ => exchange --routingKey--> serverQueue <= server => defaultExchange --> replyToQueue => consumer ✉️
    # config
    # exchange ({type: "topic", durable: true, autoDelete: false }) already exists and created by the server
    * json publishAndConsumeConfig = ({ rabbitmqClient, exchangeName: "myexchangerpc", routingKey: "my.routing.key", timeoutSeconds: 240 })
    * json headers = { header1: "foo", header2: "bar" }
    * json properties = ({ headers, contentType: "text/plain" })
    # producing
    * json message = ({ body: "ping", properties })
    * json result = rabbitmq.message.publishAndConsume({...publishAndConsumeConfig, message})
    * match result.status == "OK"
    * match result.data.body == "pong"
    * match result.data.properties contains message.properties

