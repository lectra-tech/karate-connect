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
@snowflake
Feature: Test rest

  Background:
    Given json cliConfig = read("cli-config.json")
    And string schema = "PUBLIC"
    And json snowflakeConfig = read("snowflake-config.json")
    And string jwt = snowflake.cli.generateJwt(cliConfig)
    And json restConfig = ({ jwt, cliConfig, snowflakeConfig })

  Scenario: runSql - 1 row with basic types
    When json result = snowflake.rest.runSql({...restConfig, statement: "SELECT true AS MY_BOOL, 0.123456789::double AS MY_NUMBER, 'BAR' AS MY_STRING, '2025-01-20T14:19:04.698235975+01:00'::timestamp_tz AS MY_DATE"})
    And match result.status == "OK"
    And match result.message == "Statement executed successfully."
    And table expectedOutput
      | MY_BOOL | MY_NUMBER   | MY_STRING | MY_DATE                               |
      | true    | 0.123456789 | "BAR"     | "2025-01-20T14:19:04.698235975+01:00" |
    # date with millisecond precision
    Then match result.data == expectedOutput

  Scenario: runSql - 30 lines
    Given string selectStatement = karate.map([...Array(30).keys()], (index) => "SELECT 'user"+index+"' AS USER").join("\nUNION\n")
    When def result = snowflake.rest.runSql({...restConfig, statement: selectStatement})
    Then match result.status == "OK"
    And match (result.data.length) == 30

  Scenario: cloneSchema & dropSchema
    Given string initialSchema = "DOCKER_IMAGES_KARATE_BUILD_REST_CLONE_INITIAL_"+architecture
    When json result = snowflake.rest.runSql({...restConfig, statement: "CREATE OR REPLACE SCHEMA "+initialSchema})
    And match result.status == "OK"

    Given string clonedSchema = initialSchema+"_CLONED"
    When json result = snowflake.rest.cloneSchema({...restConfig, schemaToClone: initialSchema, schemaToCreate: clonedSchema})
    And match result.status == "OK"
    And match result.message == "Statement executed successfully."

    Given json result = snowflake.rest.dropSchema({...restConfig, schemaToDrop: initialSchema})
    And match result.status == "OK"
    And match result.message == "Statement executed successfully."

    Given json result = snowflake.rest.dropSchema({...restConfig, schemaToDrop: clonedSchema})
    And match result.status == "OK"
    And match result.message == "Statement executed successfully."

  Scenario: insertRowIntoStagingTable
    Given string table = "MY_TABLE"
    And string initialSchema = "DOCKER_IMAGES_KARATE_BUILD_REST_INSERT_ROW_"+architecture
    When json result = snowflake.rest.runSql({...restConfig, statement: "CREATE OR REPLACE SCHEMA "+initialSchema})
    Then match result.status == "OK"
    And json snowflakeConfigLocal = ({...snowflakeConfig, schema: initialSchema})

    Given json restConfigLocal = ({...restConfig, snowflakeConfig: snowflakeConfigLocal})
    When json result = snowflake.rest.runSql({...restConfigLocal, statement: "CREATE OR REPLACE TABLE "+table+" (RECORD_METADATA VARIANT, RECORD_VALUE VARIANT)"})
    Then match result.status == "OK"

    Given json recordMetadata = { "foo": "bar" }
    And json recordValue = { "abc": 42 }
    When json result = snowflake.rest.insertRowIntoStagingTable({...restConfigLocal, table, recordMetadata, recordValue})
    Then match result.status == "OK"
    And match result.message == "Statement executed successfully."

    When json result = snowflake.rest.runSql({...restConfigLocal, statement: "SELECT RECORD_METADATA, RECORD_VALUE FROM "+table})
    Then match result.status == "OK"
    And match (result.data.length) == 1
    And json resultMetadata = result.data[0].RECORD_METADATA
    And json resultValue = result.data[0].RECORD_VALUE
    And match resultMetadata == recordMetadata
    And match resultValue == recordValue

    When json result = snowflake.rest.runSql({...restConfig, statement: "DROP SCHEMA IF EXISTS "+initialSchema})
    Then match result.status == "OK"

  Scenario: insertRowIntoStagingTableFromFile
    Given string table = "MY_TABLE"
    And string initialSchema = "DOCKER_IMAGES_KARATE_BUILD_REST_INSERT_ROW_FROM_FILE_"+architecture
    When json result = snowflake.rest.runSql({...restConfig, statement: "CREATE OR REPLACE SCHEMA "+initialSchema})
    Then match result.status == "OK"
    And json snowflakeConfigLocal = ({...snowflakeConfig, schema: initialSchema})

    Given json restConfigLocal = ({...restConfig, snowflakeConfig: snowflakeConfigLocal})
    When json result = snowflake.rest.runSql({...restConfigLocal, statement: "CREATE OR REPLACE TABLE "+table+" (RECORD_METADATA VARIANT, RECORD_VALUE VARIANT)"})
    Then match result.status == "OK"

    Given string recordMetadataFile = "record-metadata.json"
    And string recordValueFile = "record-value.json"
    When json result = snowflake.rest.insertRowIntoStagingTable({...restConfigLocal, table, recordMetadataFile, recordValueFile})
    Then match result.status == "OK"
    And match result.message == "Statement executed successfully."

    When json result = snowflake.rest.runSql({...restConfigLocal, statement: "SELECT RECORD_METADATA, RECORD_VALUE FROM "+table})
    Then match result.status == "OK"
    And match (result.data.length) == 1
    And json resultMetadata = result.data[0].RECORD_METADATA
    And json resultValue = result.data[0].RECORD_VALUE
    And json recordMetadata = read(recordMetadataFile)
    And json recordValue = read(recordValueFile)
    And match resultMetadata == recordMetadata
    And match resultValue == recordValue

    When json result = snowflake.rest.runSql({...restConfig, statement: "DROP SCHEMA IF EXISTS "+initialSchema})
    Then match result.status == "OK"

  Scenario: insertRowsIntoStagingTable
    Given string table = "MY_TABLE"
    And string initialSchema = "DOCKER_IMAGES_KARATE_BUILD_REST_INSERT_ROWS_"+architecture
    When json result = snowflake.rest.runSql({...restConfig, statement: "CREATE OR REPLACE SCHEMA "+initialSchema})
    Then match result.status == "OK"
    And json snowflakeConfigLocal = ({...snowflakeConfig, schema: initialSchema})

    Given json restConfigLocal = ({...restConfig, snowflakeConfig: snowflakeConfigLocal})
    When json result = snowflake.rest.runSql({...restConfigLocal, statement: "CREATE OR REPLACE TABLE MY_TABLE (RECORD_METADATA VARIANT, RECORD_VALUE VARIANT)"})
    Then match result.status == "OK"

    Given json record1 = { recordMetadata: { "foo": "bar" }, recordValue: { "abc": 42 } }
    And json record2 = { recordMetadata: { "foo": "baz" }, recordValue: { "abc": 43 } }
    When json result = snowflake.rest.insertRowsIntoStagingTable({...restConfigLocal, table, records: [ record1, record2 ]})
    Then match result.status == "OK"
    And match result.message == "Statement executed successfully."

    When json result = snowflake.rest.runSql({...restConfigLocal, statement: "SELECT RECORD_METADATA, RECORD_VALUE FROM MY_TABLE"})
    Then match result.status == "OK"
    And match (result.data.length) == 2
    And json resultMetadata = result.data[0].RECORD_METADATA
    And json resultValue = result.data[0].RECORD_VALUE
    And match resultMetadata == record1.recordMetadata
    And match resultValue == record1.recordValue
    And json resultMetadata = result.data[1].RECORD_METADATA
    And json resultValue = result.data[1].RECORD_VALUE
    And match resultMetadata == record2.recordMetadata
    And match resultValue == record2.recordValue

    When json result = snowflake.rest.runSql({...restConfig, statement: "DROP SCHEMA IF EXISTS "+initialSchema})
    Then match result.status == "OK"

  Scenario: checkTaskStatus
    Given string task = "MY_TASK"
    And string initialSchema = "DOCKER_IMAGES_KARATE_BUILD_REST_CHECK_TASK_"+architecture
    When json result = snowflake.rest.runSql({...restConfig, statement: "CREATE OR REPLACE SCHEMA "+initialSchema})
    Then match result.status == "OK"
    And json snowflakeConfigLocal = ({...snowflakeConfig, schema: initialSchema})

    Given json restConfigLocal = ({...restConfig, snowflakeConfig: snowflakeConfigLocal})
    When json result = snowflake.rest.runSql({...restConfigLocal, statement: "CREATE OR REPLACE TASK "+task+" SCHEDULE='1 MINUTE' WAREHOUSE="+snowflakeConfigLocal.warehouse+" AS SELECT 1"})
    Then match result.status == "OK"

    Given json restConfigLocal = ({...restConfig, snowflakeConfig: snowflakeConfigLocal})
    When json result = snowflake.rest.runSql({...restConfigLocal, statement: "EXECUTE TASK "+task})
    Then match result.status == "OK"

    When json result = snowflake.rest.checkTaskStatus({...restConfigLocal, taskName: task})
    Then match result.status == "OK"

    When json result = snowflake.rest.runSql({...restConfig, statement: "DROP SCHEMA IF EXISTS "+initialSchema})
    Then match result.status == "OK"

  Scenario: cloneAndExecuteTask
    # create schema
    Given string initialSchema = "DOCKER_IMAGES_KARATE_BUILD_REST_CLONE_TASK_"+architecture
    When json result = snowflake.rest.runSql({...restConfig, statement: "CREATE OR REPLACE SCHEMA "+initialSchema})
    Then match result.status == "OK"
    And json snowflakeConfigLocal = ({...snowflakeConfig, schema: initialSchema})
    And snowflakeConfigLocal.parameters = { MULTI_STATEMENT_COUNT : "4" }

    # create tasks
    Given json restConfigLocal = ({...restConfig, snowflakeConfig: snowflakeConfigLocal})
    And text statement =
      """
      CREATE OR REPLACE TASK TEST_ROOT_TASK SCHEDULE='1 MINUTE' WAREHOUSE=#(warehouse) AS SELECT 1;
      CREATE OR REPLACE TASK TEST_TASK WAREHOUSE=#(warehouse) AFTER TEST_ROOT_TASK AS SELECT 1;
      ALTER TASK TEST_TASK RESUME;
      ALTER TASK TEST_ROOT_TASK RESUME;
      """
    And replace statement.#(warehouse) = snowflakeConfigLocal.warehouse
    When json result = snowflake.rest.runSql({...restConfigLocal, statement: statement})
    Then match result.status == "OK"
    * restConfigLocal.snowflakeConfig.parameters.MULTI_STATEMENT_COUNT = "1"

    # clone and execute task
    When json result = snowflake.rest.cloneAndExecuteTask({...restConfigLocal, taskName: "TEST_TASK"})
    Then match result.status == "OK"

    # clean schema
    When json result = snowflake.rest.runSql({...restConfig, statement: "DROP SCHEMA IF EXISTS "+initialSchema})
    Then match result.status == "OK"

