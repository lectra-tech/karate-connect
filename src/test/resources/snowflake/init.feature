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
Feature: init

  @ignore @createPem
  Scenario: createPem
    # drop existing file
    * string result = karate.write("", "private-key.pem")
    * karate.exec("rm -f "+result)
    # decode key
    * string keyBase64 = karate.properties["snowflake.privateKeyBase64"]
    * if (keyBase64 == null || keyBase64 == "") karate.fail("snowflake.privateKeyBase64 property is not set")
    * karate.log("keyBase64: "+keyBase64)
    * def key = Java.type('java.util.Base64').getDecoder().decode(keyBase64)
    * def String = Java.type('java.lang.String')
    * string keyStr = new String(key, "UTF-8")
    * karate.write(keyStr, "private-key.pem")
    * karate.properties["snowflake.privateKeyPath"] = result
