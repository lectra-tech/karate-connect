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
  args = { host: "<my-host>", port: "<my-port>", virtualHost: "<my-virtual-host>", username: "<my-username>", password: "<my-password>", ssl: true|false }
    * def result = new rabbitmq.RabbitmqClient(host, port, virtualHost, username, password, ssl)
    * match result.getClass().getName() == "com.lectra.karate.connect.rabbitmq.RabbitmqClient"

  @exchange
  Scenario: exchange
  args: { rabbitmqClient: ..., name: "...", type: "topic|fanout|direct|headers", durable: true|false, autoDelete: true|false }
    * def durableValue = karate.get("durable", true)
    * def autoDeleteValue = karate.get("autoDelete", false)
    * rabbitmqClient.exchange(name, type, durableValue, autoDeleteValue)
    * json result = { status: "OK" }

  @queue
  Scenario: queue
  args : { rabbitmqClient: ..., name: "...", type: "classic|quorum", durable: true|false, exclusive: true|false, autoDelete: true|false }
    * def durableValue = karate.get("durable", true)
    * def exclusiveValue = karate.get("exclusive", false)
    * def autoDeleteValue = karate.get("autoDelete", false)
    * rabbitmqClient.queue(name, type, durableValue, exclusiveValue, autoDeleteValue)
    * json result = { status: "OK" }

  @bind
  Scenario: bind
  args : { rabbitmqClient: ..., exchangeName: "...", queueName: "...", routingKey: "..." }
    * rabbitmqClient.bind(exchangeName, queueName, routingKey)
    * json result = { status: "OK" }