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
Feature: cli

  @ignore @generateConfigToml
  Scenario: generateConfigToml
    # drop existing file
    * string configTomlPath = karate.write("", "config.toml")
    * karate.exec("rm -f "+configTomlPath)
    # create a new one
    * text configTomlContent =
    """
    [connections.default]
    authenticator = "SNOWFLAKE_JWT"

    """
    * string configTomlPath = karate.write(configTomlContent, "config.toml")
    * string chmodResult = karate.exec("chmod 0600 "+configTomlPath).trim()
    * match chmodResult == ""
    * json result = ({ configTomlPath, status: "OK" })

  @generateJwt
  Scenario: generateJwt
  args = { account: "<my-account>", user: "<my-user>", privateKeyPath: "<path>/<filename>.pem", privateKeyPassphrase: "<passphrase>" }
    * string result = karate.exec("bash -c 'PRIVATE_KEY_PASSPHRASE="+privateKeyPassphrase+" snow --config-file "+snowflake.configTomlPath+" connection generate-jwt --silent --account "+account+" --user "+user+" --private-key-file "+privateKeyPath+" 2>/dev/null'")
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
    * def snowsqlExitCode = karate.exec("bash -c 'PRIVATE_KEY_PASSPHRASE="+cliConfig.privateKeyPassphrase+" snow --config-file "+snowflake.configTomlPath+" sql --format JSON --account "+cliConfig.account+" --user "+cliConfig.user+" --role "+snowflakeConfig.role+" --warehouse "+snowflakeConfig.warehouse+" --database "+snowflakeConfig.database+" --schema "+snowflakeConfig.schema+" --filename "+sqlFile+" --private-key-path "+cliConfig.privateKeyPath+">"+logFile+"; echo \"exitCode=$?\"'")
    * string log = karate.readAsString("file:"+logFile)
    * if (!snowsqlExitCode.contains("exitCode=0")) karate.log(log)
    * karate.exec("rm -f "+sqlFile)
    * karate.exec("rm -f "+logFile)
    * if (!snowsqlExitCode.contains("exitCode=0")) karate.fail(karate.scenario.name+" has failed")
    * json logJson = log
    * result.status = "OK"
    * result.output = logJson
