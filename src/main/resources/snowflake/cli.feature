##
 # Copyright (C) 2026 Lectra
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
Feature: cli

  @generateJwt
  Scenario: generateJwt
  args = { account: "<my-account>", user: "<my-user>", privateKeyPath: "<path>/<filename>.pem", privateKeyPassphrase: "<passphrase>" }
    * string result = karate.exec("bash -c 'PRIVATE_KEY_PASSPHRASE="+privateKeyPassphrase+" snow connection generate-jwt --silent --temporary-connection --authenticator SNOWFLAKE_JWT --account "+account+" --user "+user+" --private-key-file "+privateKeyPath+" 2>/dev/null'").trim()
    * match result == "#regex .+\\..+\\..+"

  @ignore @putFileIntoTable
  Scenario: putFileIntoTable
  args = { sqlFile: "xxx.sql", fileAbsolutePath: "<file-absolute-path>", tableName: "XXX", cliConfig: { ... }, snowflakeConfig: { ... } }
    * def statement = karate.readAsString("classpath:snowflake/"+sqlFile)
    * replace statement.#(filePath) = fileAbsolutePath
    * replace statement.#(stageName) = ("STAGE_" + base.random.uuid().replaceAll("-", "_").toUpperCase())
    * replace statement.#(tableName) = tableName
    * json result = karate.call("@runSql", { statement, cliConfig, snowflakeConfig }).result

  @putCsvIntoTable
  Scenario: putCsvIntoTable
  args = { fileAbsolutePath: "<file-absolute-path>", tableName: "XXX", cliConfig: { ... }, snowflakeConfig: { ... } }
    * json result = karate.call("@putFileIntoTable", { sqlFile: "putCsvIntoTable.sql", fileAbsolutePath, tableName, cliConfig, snowflakeConfig }).result

  @putJsonIntoTable
  Scenario: putJsonIntoTable
  args = { fileAbsolutePath: "<file-absolute-path>", tableName: "XXX", cliConfig: { ... }, snowflakeConfig: { ... } }
    * json result = karate.call("@putFileIntoTable", { sqlFile: "putJsonIntoTable.sql", fileAbsolutePath, tableName, cliConfig, snowflakeConfig }).result

  @runSql
  Scenario: runSql
  args = { statement: "...", cliConfig: { ... }, snowflakeConfig: { ... } }
    * json result = { "status": "WIP" }
    * def sqlFile = karate.write(statement, base.random.uuid() + ".sql")
    * def logFile = karate.write("", base.random.uuid() + ".log")
    * def commandResult = karate.exec("bash -c 'PRIVATE_KEY_PASSPHRASE="+cliConfig.privateKeyPassphrase+" snow sql --temporary-connection --authenticator SNOWFLAKE_JWT --format JSON --account "+cliConfig.account+" --user "+cliConfig.user+" --role "+snowflakeConfig.role+" --warehouse "+snowflakeConfig.warehouse+" --database "+snowflakeConfig.database+" --schema "+snowflakeConfig.schema+" --filename "+sqlFile+" --private-key-path "+cliConfig.privateKeyPath+" > " + logFile + " 2>&1; echo \"exitCode=$?\"'").trim()
    * def log = karate.read("file:"+logFile)
    * result.status = (commandResult == "exitCode=0" ? "OK" : "FAILED")
    * if (result.status == "OK") result.output = JSON.parse(log)
    * if (result.status != "OK") result.output = log
    * karate.exec("rm -f "+sqlFile)
    * karate.exec("rm -f "+logFile)
