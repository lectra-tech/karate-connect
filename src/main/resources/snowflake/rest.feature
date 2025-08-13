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
Feature: rest

  @ignore @prepareUrlHeaders
  Scenario: prepareUrlHeaders
  args = { jwt: "...", cliConfig: {... } }
    * string snowflakeApiUrl = "https://" + cliConfig.account + ".snowflakecomputing.com/api/v2"
    * json headers = { "Content-Type": "application/json", "Accept": "application/json", "X-Snowflake-Authorization-Token-Type": "KEYPAIR_JWT" }
    * headers["Authorization"] = "Bearer " + jwt
    * headers["User-Agent"] = "karate/" + (karate.get("projectName") == null ? "unknownProjectName" : projectName)

  @ignore @preparePayload
  Scenario: preparePayload
  args = { statement: "...", snowflakeConfig: { ... } }
    * json payload = ({ ...snowflakeConfig, statement: statement })
    * if (!payload["timeout"]) { payload.timeout = 60 }
    * if (!payload["parameters"]) { payload.parameters = { "TIMESTAMP_TZ_OUTPUT_FORMAT": "YYYY-MM-DDTHH24:MI:SS.FFTZH:TZM", "TIMESTAMP_NTZ_OUTPUT_FORMAT": "YYYY-MM-DDTHH24:MI:SS.FF", "DATE_OUTPUT_FORMAT": "YYYY-MM-DD" } }

  @ignore @wait200
  Scenario: wait200
  args = { statementHandle: "...", snowflakeApiUrl: "...", headers: { ... } }
    Given url snowflakeApiUrl
    And headers headers
    And path "statements", statementHandle
    * retry until responseStatus == 200
    When method get

  @runSql
  Scenario: runSql
  args = { statement: "...", jwt: "...", cliConfig: {... }, snowflakeConfig: { ... } }
    * json result = { "status": "WIP" }
    Given json preparateRunSql = karate.call("@prepareUrlHeaders", { cliConfig, jwt })
    And url preparateRunSql.snowflakeApiUrl
    And headers preparateRunSql.headers
    And path "statements"
    And json payload = karate.call("@preparePayload", { statement, snowflakeConfig }).payload
    And request payload
    And retry until responseStatus >= 200 && responseStatus < 300
    When method post
    * if (responseStatus == 202) { response = karate.call("@wait200", { statementHandle: response.statementHandle, snowflakeApiUrl: preparateRunSql.snowflakeApiUrl, headers: preparateRunSql.headers}).response }
    * if (responseStatus >= 400) karate.fail(JSON.stringify(response))
    * result.statementHandle = response.statementHandle
    * result.message = response.message
    * result.status = "OK"
    * def extractValue =
    """
    function(columnType, value) {
      switch (columnType) {
        case 'boolean':
          return eval(value);
        case 'real':
          return eval(value);
        case 'fixed':
          return eval(value);
        default:
          return value;
      }
    }
    """
    * result.data = karate.map(response.data, (row) => response.resultSetMetaData.rowType.reduce((out, column, index) => ((out[column.name] = extractValue(column.type, row[index])), out), {}))

  @cloneSchema
  Scenario: cloneSchema
  args = { "schemaToClone": "xxx", "schemaToCreate": "yyy", jwt: "...", cliConfig: { ... }, "snowflakeConfig": { ... } }
    * karate.log("Cloning schema "+schemaToClone+" to "+schemaToCreate)
    * json result = karate.call("@runSql", { statement: "CREATE SCHEMA "+schemaToCreate+" CLONE "+schemaToClone, jwt, cliConfig, snowflakeConfig }).result

  @dropSchema
  Scenario: dropSchema
  args = { "schemaToDrop": "xxx", cliConfig: { ... }, "snowflakeConfig": { ... }, jwt: "... Optional" }
    * karate.log("Dropping schema "+schemaToDrop)
    * json result = karate.call("@runSql", { statement: "DROP SCHEMA IF EXISTS "+schemaToDrop, jwt, cliConfig, snowflakeConfig }).result

  @ignore @recordToString
  Scenario: recordToString
  args = { "recordMetadata": {...}, "recordValue": {...} }
    * string rm = recordMetadata
    * string rv = recordValue
    * string result = "('"+rm+"','"+rv+"')"

  @insertRowIntoStagingTable
  Scenario: insertRowIntoStagingTable
  args = { "table": "MY_TABLE", "recordMetadata": {...}, "recordMetadataFile": "...", "recordValue": {...}, "recordValueFile": "...", jwt: "...", cliConfig: { ... }, "snowflakeConfig": { ... } }
    * json metadata = (karate.get("recordMetadata") != null ? recordMetadata : karate.read(recordMetadataFile))
    * json value = (karate.get("recordValue") != null ? recordValue : karate.read(recordValueFile))
    * string recordToString = karate.call("@recordToString", { recordMetadata: metadata, recordValue: value }).result
    * json result = karate.call("@runSql", { statement: "INSERT INTO "+table+" SELECT PARSE_JSON(column1), PARSE_JSON(column2) FROM VALUES "+recordToString, jwt, cliConfig, snowflakeConfig }).result

  @insertRowsIntoStagingTable
  Scenario: insertRowsIntoStagingTable
  args = { "table": "MY_TABLE", "records": [ {"recordMetadata": {...}, "recordValue": {...}}, ... ], cliConfig: { ... }, "snowflakeConfig": { ... }, jwt: "... Optional" }
    * string values = ""
    * karate.forEach(records, (record) => values+=karate.call("@recordToString", record).result+",")
    * json result = karate.call("@runSql", { statement: "INSERT INTO "+table+" SELECT PARSE_JSON(column1), PARSE_JSON(column2) FROM VALUES "+values.slice(0, -1), jwt, cliConfig, snowflakeConfig }).result

  @checkTaskStatus
  Scenario: checkTaskStatus
  args = { taskName: "MY_TASK", cliConfig: { ... }, "snowflakeConfig": { ... }, jwt: "... Optional" }
    * json result = { "status": "WIP" }
    Given json preparateRunSql = karate.call("@prepareUrlHeaders", { cliConfig, jwt })
    And url preparateRunSql.snowflakeApiUrl
    And headers preparateRunSql.headers
    And path "statements"
    And def statement = "SELECT TOP 1 COMPLETED_TIME, STATE, ERROR_CODE, ERROR_MESSAGE FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY(TASK_NAME=>'"+taskName+"')) WHERE DATABASE_NAME = '"+snowflakeConfig.database+"' and SCHEDULED_FROM='EXECUTE TASK' ORDER BY SCHEDULED_TIME desc"
    And json checkRequest = karate.call("@preparePayload", { statement, snowflakeConfig }).payload
    And retry until responseStatus == 200 && response.data.length != 0 && response.data[0][0] != null
    When request checkRequest
    And method post
    And match response.resultSetMetaData.numRows == 1
    And match response.data[0][1] == "SUCCEEDED"
    * result.status = "OK"

  @cloneAndExecuteTask
  Scenario: cloneAndExecuteTask
  args = { taskName: "MY_TASK_NAME", jwt: "...", cliConfig: { ... }, snowflakeConfig: { ... } }
    # generate task request without parent
    Given string ddlStatement = "SELECT REGEXP_REPLACE(REGEXP_REPLACE(GET_DDL('task', '"+taskName+"'), '(task\\\\s+[^\\\\s]+)', '\\\\1_TEMPORARY '),'after\\\\s+[^\\\\s]+','') AS DDL"
    When json result = snowflake.rest.runSql({ statement: ddlStatement, jwt, cliConfig, snowflakeConfig })
    Then match result.status == "OK"
    And string taskStatement = result.data[0].DDL

    # create task
    When json result = snowflake.rest.runSql({ statement: taskStatement, jwt, cliConfig, snowflakeConfig })
    Then match result.status == "OK"

    # execute task
    Given string executeTaskStatement = "EXECUTE TASK "+taskName+"_TEMPORARY"
    When json result = snowflake.rest.runSql({ statement: executeTaskStatement, jwt, cliConfig, snowflakeConfig })
    Then match result.status == "OK"

    # check
    When json result = karate.call("@checkTaskStatus", { taskName: taskName+"_TEMPORARY", jwt, cliConfig, snowflakeConfig}).result
    Then match result.status == "OK"

    # drop cloned task
    Given string dropTaskStatement = "DROP TASK IF EXISTS "+taskName+"_TEMPORARY"
    When json result = snowflake.rest.runSql({statement: dropTaskStatement, jwt, cliConfig, snowflakeConfig })
    Then match result.status == "OK"
