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
Feature: Test cli

  Background:
    Given json cliConfig = read("cli-config.json")
    * configure afterScenario = function() { karate.call('@clean') }

  @ignore @clean
  Scenario: clean
    Given string scenario = karate.get("scenario", "NONE")
    And string statement = "DROP SCHEMA IF EXISTS DOCKER_IMAGES_KARATE_BUILD_CLI_"+scenario
    And string schema = "PUBLIC"
    And json snowflakeConfigLocal = read("snowflake-config.json")
    * if (scenario != "NONE") { snowflake.cli.runSql({statement, cliConfig, snowflakeConfig: snowflakeConfigLocal}) }

  Scenario: runSql
    Given string schema = "PUBLIC"
    And json snowflakeConfigLocal = read("snowflake-config.json")
    When def result = snowflake.cli.runSql({statement: "SELECT 0.123456789::double AS MY_NUMBER, 'BAR' AS MY_STRING, '2025-01-20T14:19:04.698235975+01:00'::timestamp_tz AS MY_DATE", cliConfig, snowflakeConfig: snowflakeConfigLocal})
    Then match result.status == "OK"
    And table expectedOutput
      | MY_NUMBER   | MY_STRING | MY_DATE                            |
      | 0.123456789 | "BAR"     | "2025-01-20T14:19:04.698235+01:00" |
    # date with millisecond precision
    And match result.output == expectedOutput

  Scenario: runSql - 30 lines
    Given string schema = "PUBLIC"
    And json snowflakeConfigLocal = read("snowflake-config.json")
    And string selectStatement = karate.map([...Array(30).keys()], (index) => "SELECT 'user"+index+"' AS USER").join("\nUNION\n")
    When def result = snowflake.cli.runSql({statement: selectStatement, cliConfig, snowflakeConfig: snowflakeConfigLocal})
    Then match result.status == "OK"
    And match (result.output.length) == 30

  Scenario: generateJwt
    Given def parseJwt =
      """
      function (token) {
        var String = Java.type('java.lang.String');
        return new String(Java.type('java.util.Base64').getUrlDecoder().decode(token.split('.')[1]));
      }
      """
    When string jwt = snowflake.cli.generateJwt(cliConfig)
    Then match jwt == '#notnull'
    And def jwtParsed = parseJwt(jwt)
    And match jwtParsed == '#notnull'

  Scenario Outline: <method>
    Given string scenario = "<format>_"+architecture
    And string schema = "DOCKER_IMAGES_KARATE_BUILD_CLI_"+scenario
    And json snowflakeConfigIT = read("snowflake-config.json")
    And text createStatement =
      """
      CREATE OR REPLACE SCHEMA DOCKER_IMAGES_KARATE_BUILD_CLI_<scenario>;
      CREATE OR REPLACE TABLE MY_TABLE_<format>(FOO NUMBER, BAR STRING, TEST STRING);
      """
    And replace createStatement.scenario = scenario
    And json create = snowflake.cli.runSql({statement: createStatement, cliConfig, snowflakeConfig: snowflakeConfigIT})

    Given json params = ({fileAbsolutePath: karate.toAbsolutePath("../files/<file>"), tableName: "MY_TABLE_<format>", cliConfig, snowflakeConfig: snowflakeConfigIT})
    When json result = snowflake.cli.<method>(params)
    And match result.status == "OK"

    Given json params = ({statement: "SELECT FOO, BAR, TEST FROM MY_TABLE_<format>", snowflakeConfig: snowflakeConfigIT})
    When json result = snowflake.cli.runSql(params)
    Then match result.output == [{ "FOO":1, "BAR":"bar1", "TEST":"test1" }, { "FOO":2, "BAR":"bar2", "TEST":"test2" }]

    Examples:
      | format | file                 | method           |
      | CSV    | test.csv             | putCsvIntoTable  |
      | JSON   | test-json-lines.json | putJsonIntoTable |
