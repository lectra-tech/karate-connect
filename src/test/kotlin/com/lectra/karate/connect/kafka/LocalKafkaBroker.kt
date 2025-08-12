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

import com.lectra.karate.connect.LocalBroker
import io.github.embeddedkafka.schemaregistry.EmbeddedKafka
import io.github.embeddedkafka.schemaregistry.EmbeddedKafkaConfig
import org.apache.kafka.clients.CommonClientConfigs
import org.apache.kafka.clients.admin.AdminClient
import org.apache.kafka.clients.admin.NewTopic

class LocalKafkaBroker(
    private val kafkaPort: Int = LocalBroker.freePort(),
    private val controllerPort: Int = LocalBroker.freePort(),
    private val schemaRegistryPort: Int = LocalBroker.freePort()
) : LocalBroker {

    private val adminClient = AdminClient.create(
        mapOf(CommonClientConfigs.BOOTSTRAP_SERVERS_CONFIG to bootstrapServers())
    )

    override fun start() {
        val mapScala = scala.collection.immutable.HashMap<String, String>()
        EmbeddedKafka.start(
            EmbeddedKafkaConfig.apply(
                kafkaPort,
                controllerPort,
                schemaRegistryPort,
                mapScala,
                mapScala,
                mapScala,
                mapScala
            )
        )
    }

    override fun stop() {
        adminClient.close()
        EmbeddedKafka.stop()
    }

    fun bootstrapServers(): String {
        return "localhost:$kafkaPort"
    }

    fun schemaRegistryUrl(): String {
        return "http://localhost:$schemaRegistryPort"
    }

    fun createTopic(topicName: String) {
        val newTopic = NewTopic(topicName, 1, 1)
        adminClient.createTopics(listOf(newTopic)).all().get()
    }

    fun listTopics(): List<String> {
        val topics = adminClient.listTopics().names().get()
        return topics.toList()
    }

}
