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
function fn() {
    karate.log("Karate Ext Config Kafka");
    const KafkaClient = Java.type("com.lectra.karate.connect.kafka.KafkaClient");

    const kafkaConfigFromEnv = (() => {
        const consumerPrefix = java.lang.System.getenv("KAFKA_KARATE_CONNECT_CONSUMER_GROUP_ID_PREFIX");
        const config = {
            "bootstrap.servers": java.lang.System.getenv("KAFKA_BOOTSTRAP_SERVERS"),
            "schema.registry.url": java.lang.System.getenv("KAFKA_SCHEMA_REGISTRY_URL"),
            "karate.connect.consumer.group.id.prefix": (consumerPrefix ? consumerPrefix : ""),
        };
        if (java.lang.System.getenv("KAFKA_SCHEMA_REGISTRY_BASIC_AUTH_CREDENTIALS_SOURCE") === "USER_INFO") {
            config["basic.auth.credentials.source"] = schemaRegistryBasicAuthCredentialsSource;
            config["basic.auth.user.info"] = java.lang.System.getenv("KAFKA_SCHEMA_REGISTRY_KEY") + ":" + java.lang.System.getenv("KAFKA_SCHEMA_REGISTRY_SECRET");
        }
        return config;
    })();
    const kafkaConfigSaslFromEnv = (() => {
        const config = {...kafkaConfigFromEnv};
        config["security.protocol"] = java.lang.System.getenv("KAFKA_SECURITY_PROTOCOL");
        config["sasl.mechanism"] = java.lang.System.getenv("KAFKA_SASL_MECHANISM");
        const loginModule = (config["sasl.mechanism"] === "PLAIN" ? "org.apache.kafka.common.security.plain.PlainLoginModule" : "org.apache.kafka.common.security.scram.ScramLoginModule");
        config["sasl.jaas.config"] = (loginModule + " required username='" + java.lang.System.getenv("KAFKA_USERNAME") + "' password='" + java.lang.System.getenv("KAFKA_PASSWORD") + "';");
        return config;
    })();
    const defaultConfig = {
        "configFromEnv": kafkaConfigFromEnv,
        "configSaslFromEnv": kafkaConfigSaslFromEnv,
        "KafkaClient": KafkaClient
    };

    const generatedConfig = karate.read('classpath:kafka/kafka.js');
    return {
        ...defaultConfig,
        ...generatedConfig
    };
}