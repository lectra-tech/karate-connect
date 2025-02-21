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
    karate.log("Karate Ext Config Rabbitmq");

    const RabbitmqClient = Java.type("com.lectra.karate.connect.rabbitmq.RabbitmqClient");
    const Message = Java.type("com.lectra.karate.connect.rabbitmq.Message");

    const rabbitmqConfigFromEnv = {
        host: java.lang.System.getenv("RABBITMQ_HOST"),
        port: parseInt(java.lang.System.getenv("RABBITMQ_PORT")),
        virtualHost: java.lang.System.getenv("RABBITMQ_VIRTUAL_HOST"),
        username: java.lang.System.getenv("RABBITMQ_USERNAME"),
        password: java.lang.System.getenv("RABBITMQ_PASSWORD"),
        ssl: java.lang.System.getenv("RABBITMQ_SSL") === 'true',
    };
    const defaultConfig = {
        "configFromEnv": rabbitmqConfigFromEnv,
        "RabbitmqClient": RabbitmqClient,
        "Message": Message
    };

    const generatedConfig = karate.read('classpath:rabbitmq/rabbitmq.js');
    return {
        ...defaultConfig,
        ...generatedConfig
    };
}