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
package com.lectra.karate.connect.rabbitmq

import com.rabbitmq.client.*
import org.awaitility.kotlin.await
import org.slf4j.LoggerFactory
import java.io.IOException
import java.nio.charset.StandardCharsets
import java.util.*
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import javax.net.ssl.SSLContext


/**
 * @see "https://github.com/rabbitmq/rabbitmq-tutorials/tree/main/java"
 */
class RabbitmqClient(
    private val host: String,
    private val port: Int,
    private val virtualHost: String,
    private val username: String,
    private val password: String,
    private val ssl: Boolean
) : AutoCloseable {
    private val LOGGER = LoggerFactory.getLogger(RabbitmqClient::class.java)

    private fun initConnection(): Connection {
        val self = this
        return ConnectionFactory().apply {
            this.host = self.host
            this.port = self.port
            this.virtualHost = self.virtualHost
            this.username = self.username
            this.password = self.password
            if (self.ssl) {
                this.useSslProtocol(SSLContext.getDefault())
            }
            this.isAutomaticRecoveryEnabled = true
        }.newConnection()
    }

    private val rabbitmqConnection: AtomicReference<Connection> = logExecution("Creating connection") {
        AtomicReference(initConnection())
    }

    private fun handleConnection() = rabbitmqConnection.updateAndGet { if (it.isOpen) it else initConnection() }

    override fun close() {
        rabbitmqConnection.updateAndGet { conn ->
            controlChannel.updateAndGet { if (it.isOpen) logExecution("Closing control channel") { it.close() }; it }
            readChannel.updateAndGet { if (it.isOpen) logExecution("Closing read channel") { it.close() }; it }
            writeChannel.updateAndGet { if (it.isOpen) logExecution("Closing write channel") { it.close() }; it }
            if (conn.isOpen) logExecution("Closing connection") { conn.close() }
            conn
        }
    }

    private val readChannel: AtomicReference<Channel> = logExecution("Creating read channel") {
        AtomicReference(handleConnection().createChannel())
    }

    private val writeChannel: AtomicReference<Channel> = logExecution("Creating write channel") {
        AtomicReference(handleConnection().createChannel())
    }

    private val controlChannel: AtomicReference<Channel> = logExecution("Creating control channel") {
        AtomicReference(handleConnection().createChannel())
    }

    private fun handleChannel(channel: AtomicReference<Channel>) =
        channel.updateAndGet({ if (it.isOpen) it else handleConnection().createChannel() })

    init {
        logExecution("Initializing ${this.javaClass.simpleName}") {
            Runtime.getRuntime().addShutdownHook(Thread {
                logExecution("Closing ${this.javaClass.simpleName}") {
                    close()
                }
            })
        }
    }

    private fun <T> logExecution(message: String, block: () -> T): T {
        val text = "$message..."
        LOGGER.info(text)
        val result = try {
            block()
        } catch (e: IOException) {
            LOGGER.error("${text}FAILED", e.cause)
            throw e
        } catch (t: Throwable) {
            LOGGER.error("${text}FAILED", t)
            throw t
        }
        LOGGER.info("${text}DONE")
        return result
    }

    fun exchange(name: String, type: String, durable: Boolean, autoDelete: Boolean) {
        logExecution("Creating exchange $name") {
            handleChannel(controlChannel).exchangeDeclare(name, type, durable, autoDelete, emptyMap())
        }
    }

    fun queue(name: String, type: String, durable: Boolean, exclusive: Boolean, autoDelete: Boolean) {
        logExecution("Creating queue $name") {
            handleChannel(controlChannel).queueDeclare(
                name,
                durable,
                exclusive,
                autoDelete,
                mapOf("x-queue-type" to type)
            )
        }
    }

    fun bind(exchangeName: String, queueName: String, bindingKey: String) {
        logExecution("Binding exchange $exchangeName --$bindingKey--> queue $queueName") {
            handleChannel(controlChannel).queueBind(queueName, exchangeName, bindingKey)
        }
    }

    fun publish(exchangeName: String, routingKey: String, message: Message) {
        logExecution("Producing message to exchange $exchangeName --$routingKey-->") {
            handleChannel(writeChannel).basicPublish(
                exchangeName, routingKey, message.properties, message.body
            )
            LOGGER.debug(
                "Message[{}] sent to exchange[{}] with routingKey[{}]",
                message.bodyToString(),
                exchangeName,
                routingKey
            )
        }
    }

    fun consume(queueName: String, timeoutSeconds: Long = 60, minNbMessages: Long = 1): List<Message> =
        consume(queueName = queueName, timeoutSeconds = timeoutSeconds) { messages ->
            messages.size >= minNbMessages
        }


    private fun consumeOnCorrelationId(queueName: String, correlationId: String, timeoutSeconds: Long = 60): Message =
        consume(queueName = queueName, timeoutSeconds = timeoutSeconds) { messages ->
            messages.any { it.properties.correlationId == correlationId }
        }.first()

    private fun consume(
        queueName: String,
        timeoutSeconds: Long = 60,
        block: (List<Message>) -> Boolean
    ): List<Message> {
        return logExecution("Opening message consumption from queue $queueName") {
            val response = AtomicReference(emptyList<Message>())
            val deliverCallback = DeliverCallback { consumerTag: String?, delivery: Delivery ->
                val message = Message(delivery.body, delivery.properties)
                LOGGER.debug(
                    "Message[{}] consumed from queue[{}] with routingKey[{}]",
                    message.bodyToString(),
                    queueName,
                    delivery.envelope.routingKey
                )
                response.accumulateAndGet(listOf(message)) { acc, list -> acc + list }
            }
            handleChannel(readChannel).basicConsume(queueName, true, deliverCallback) { _ -> }
            await.atMost(timeoutSeconds, TimeUnit.SECONDS).until { block(response.get()) }
            response.get()
        }
    }

    fun publishAndConsume(
        exchangeName: String,
        routingKey: String,
        message: Message,
        timeoutSeconds: Long = 60
    ): Message {
        val (messageToSend, queueName) = if (message.properties.replyTo == null) {
            val queueName = "replyTo-${UUID.randomUUID()}"
            queue(name = queueName, type = "classic", durable = false, exclusive = false, autoDelete = true)
            Pair(Message(message.body, message.properties.builder().replyTo(queueName).build()), queueName)
        } else Pair(message, message.properties.replyTo)
        publish(exchangeName = exchangeName, routingKey = routingKey, message = messageToSend)
        return consumeOnCorrelationId(
            queueName = queueName,
            correlationId = message.properties.correlationId,
            timeoutSeconds = timeoutSeconds
        )
    }

}

class Message(val body: ByteArray, val properties: AMQP.BasicProperties) {
    fun bodyToString(): String {
        return String(body, properties.contentEncoding?.let { charset(it) } ?: StandardCharsets.UTF_8)
    }

    fun propertiesToMap(): Map<String, Any?> {
        return mapOf(
            "contentType" to properties.contentType,
            "contentEncoding" to properties.contentEncoding,
            "deliveryMode" to properties.deliveryMode,
            "priority" to properties.priority,
            "correlationId" to properties.correlationId,
            "replyTo" to properties.replyTo,
            "expiration" to properties.expiration,
            "messageId" to properties.messageId,
            "timestamp" to properties.timestamp?.time,
            "type" to properties.type,
            "userId" to properties.userId,
            "appId" to properties.appId,
            "clusterId" to properties.clusterId,
            "headers" to (properties.headers?.entries ?: emptyMap<String, Any>().entries)
                .associate { it.key to it.value?.toString() }
                .filter { it.value != null }
        )
    }

    fun toMap(): Map<String, Any> {
        return mapOf(
            "body" to bodyToString(),
            "properties" to propertiesToMap()
        )
    }

    companion object {
        @JvmStatic
        fun from(body: String, properties: Map<String, Any?>): Message {
            val builder = MessageProperties.MINIMAL_BASIC.builder()
            // properties
            properties.getOrDefault("contentType", "application/json").let { builder.contentType(it.toString()) }
            properties.getOrDefault("contentEncoding", StandardCharsets.UTF_8.toString())
                .let { builder.contentEncoding(it.toString()) }
            properties["deliveryMode"]?.let { builder.deliveryMode(it as Int) }
            properties["priority"]?.let { builder.priority(it as Int) }
            properties.getOrDefault("correlationId", UUID.randomUUID().toString())
                .let { builder.correlationId(it.toString()) }
            properties["replyTo"]?.let { builder.replyTo(it.toString()) }
            properties["expiration"]?.let { builder.expiration(it.toString()) }
            properties.getOrDefault("messageId", UUID.randomUUID().toString()).let { builder.messageId(it.toString()) }
            properties.getOrDefault("timestamp", System.currentTimeMillis())
                .let { builder.timestamp(Date(it as Long)) } // the milliseconds since January 1, 1970, 00:00:00 GMT
            properties["type"]?.let { builder.type(it.toString()) }
            properties["userId"]?.let { builder.userId(it.toString()) }
            properties["appId"]?.let { builder.appId(it.toString()) }
            properties["clusterId"]?.let { builder.clusterId(it.toString()) }
            // headers
            properties["headers"]?.let { builder.headers(it as Map<String, Any?>) }
            // result
            val amqpProperties = builder.build()
            return Message(body.toByteArray(amqpProperties.contentEncoding?.let { charset(it) }
                ?: StandardCharsets.UTF_8), amqpProperties)
        }
    }

}