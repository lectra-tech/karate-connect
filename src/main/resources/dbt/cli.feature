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

  @run
  Scenario: run
  args = { select: "...", profilesDir: "...", projectDir: "...", extra: "...", env: { "X": "valueX", "Y": "valueY", ...}} }
    * string selectValue = (karate.get("select") != null ? "--select " + select : "")
    * string profilesDirValue = (karate.get("profilesDir") != null ? "--profiles-dir " + profilesDir : "")
    * string projectDirValue = (karate.get("projectDir") != null ? "--project-dir " + projectDir : "")
    * string extraValue = karate.get("extra", "")
    * json result = { status : "WIP" }
    * string dbtCommand = "dbt run "+selectValue+" "+profilesDirValue+" "+projectDirValue+" "+extraValue
    * string execCommand = (karate.get("env") != null ? "bash -c '"+Object.keys(env).map((k) => k + "=" + env[k]).join(" ")+" "+dbtCommand+"'" : dbtCommand) 
    * result.output = karate.exec(execCommand)
    * result.status = (result.output.contains("Completed successfully") ? "OK" : "FAILED")
