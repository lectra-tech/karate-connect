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
    karate.log("Karate Ext Config Snowflake");

    karate.configure("retry", {count: 10, interval: 5000});
    karate.configure("readTimeout", 240000);

    const configTomlPath = karate.callSingle("classpath:snowflake/cli.feature@generateConfigToml").result.configTomlPath;

    const cliConfigFromEnv = {
        account: java.lang.System.getenv('SNOWFLAKE_ACCOUNT'),
        user: java.lang.System.getenv('SNOWFLAKE_USER'),
        privateKeyPath: java.lang.System.getenv('SNOWFLAKE_PRIVATE_KEY_PATH'),
        privateKeyPassphrase: java.lang.System.getenv('PRIVATE_KEY_PASSPHRASE')
    };
    const snowflakeConfigFromEnv = {
        role: java.lang.System.getenv('SNOWFLAKE_ROLE'),
        warehouse: java.lang.System.getenv('SNOWFLAKE_WAREHOUSE'),
        database: java.lang.System.getenv('SNOWFLAKE_DATABASE'),
        schema: java.lang.System.getenv('SNOWFLAKE_SCHEMA'),
    };
    const defaultConfig = {
        "configTomlPath": configTomlPath,
        "cliConfigFromEnv": cliConfigFromEnv,
        "snowflakeConfigFromEnv": snowflakeConfigFromEnv
    };

    const generatedConfig = karate.read('classpath:snowflake/snowflake.js');
    return {
        ...defaultConfig,
        ...generatedConfig
    };
}