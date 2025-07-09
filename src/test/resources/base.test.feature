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
@base
Feature: Test base

  Scenario: random.uuid
    When string generatedUUID = base.random.uuid()
    Then match generatedUUID == '#uuid'

  Scenario: time.currentTimeMillis
    When def result = base.time.currentTimeMillis()
    Then match result == '#number ? _ > 0'

  Scenario: bug JSON.stringify
    https://github.com/karatelabs/karate/issues/2581
    Given json myJson = { "myField":  0.10738338032073512 }
    When string value = JSON.stringify(myJson)
    And string value2 = (myJson)
    Then match value == '{"myField":{}}'
    Then match value2 == '{"myField":0.10738338032073512}'

  Scenario: json.toString
    Given json myJson = { "myField":  0.10738338032073512 }
    When def value = base.json.toString(myJson)
    Then match value == '{"myField":0.10738338032073512}'

  Scenario: json.readLines
    Given def bar1 = "valueBar1"
    And def test = "valueTest"
    And def foo2 = 2
    And def myDate = java.time.OffsetDateTime.of(2020, 1, 1, 0, 0, 0, 0, java.time.ZoneOffset.UTC)
    And string jsonContent = base.json.readLines("files/test-json-lines-token.json")
    And text expected =
      """
      {"FOO":1,"BAR":"valueBar1","TEST":"prefix-valueTest-suffix","DATE":"2020-01-01T00:00Z"}
      {"FOO":2,"BAR":"baz","TEST":"prefix-valueTest-suffix","DATE":"2020-01-01T00:00Z"}
      """
    And match jsonContent.trim() == expected.trim()

  Scenario: time.offsetDateTimeNow
    When def now = base.time.offsetDateTimeNow()
    Then match now == '#regex ^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}\\.\\d{6,9}([+-]\\d{2}:\\d{2}|Z)$'

  Scenario: assert.withEpsilon
    Given json myObject = { "foo": 0.123456789, "bar": 12.3456789E-2 }
    When def goodAssertion1 = base.assert.withEpsilon(myObject.foo, 0.1234, 0.0001)
    And def goodAssertion2 = base.assert.withEpsilon(myObject.foo, 0.1235, 0.0001)
    And def badAssertion = base.assert.withEpsilon(myObject.foo, 0.1236, 0.0001)
    When def goodAssertion1bis = base.assert.withEpsilon(myObject.bar, 1.234E-1, 1E-4)
    And def goodAssertion2bis = base.assert.withEpsilon(myObject.bar, 1.235E-1, 1E-4)
    And def badAssertionbis = base.assert.withEpsilon(myObject.bar, 1.236E-1, 1E-4)
    Then match goodAssertion1 == true
    And match goodAssertion2 == true
    And match badAssertion == false
    And match goodAssertion1bis == true
    And match goodAssertion2bis == true
    And match badAssertionbis == false

  Scenario: jsonPath
    Given json myArray = [ { "foo": 1, "bar": "toto" }, { "foo": 2, "bar": "tutu" } ]
    When def filteredArray = karate.jsonPath(myArray, "$[?(@.foo == 1)]")
    Then match filteredArray[0] contains { "bar": "toto" }

  Scenario: tables
    Given table myTable
      | foo | bar    |
      | 1   | "toto" |
      | 2   | "tutu" |
    Then match myTable == [{ "foo": 1, "bar": "toto" }, { "foo": 2, "bar": "tutu" }]

    Given set myTable2
      | path            | value  |
      | name.first_name | "John" |
      | name.last_name  | "Doe"  |
      | age             | 25     |
    Then match myTable2 == { "name": { "first_name": "John", "last_name": "Doe" }, "age": 25 }

    Given set myTable3
      | path | 0     | 1     |
      | name | "foo" | "bar" |
    Then match myTable3 == [{ "name": "foo" }, { "name": "bar" }]

  Scenario Outline: hash.<algorithm>
    Given string data = <data>
    When string hash = base.hash.<algorithm>(data)
    Then match hash == <expectedHash>

    Examples:
      | algorithm | data          | expectedHash                                                                                                                       |
      | md5       | "hello world" | "5eb63bbbe01eeed093cb22bb8f5acdc3"                                                                                                 |
      | sha1      | "hello world" | "2aae6c35c94fcfb415dbe95f408b9ce91ee846ed"                                                                                         |
      | sha224    | "hello world" | "2f05477fc24bb4faefd86517156dafdecec45b8ad3cf2522a563582b"                                                                         |
      | sha256    | "hello world" | "b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9"                                                                 |
      | sha384    | "hello world" | "fdbd8e75a67f29f701a4e040385e2e23986303ea10239211af907fcbb83578b3e417cb71ce646efd0819dd8c088de1bd"                                 |
      | sha512    | "hello world" | "309ecc489c12d6eb4cc40f50c902f2b4d0ed77ee511a7c7a9bcd3ca86d4cd86f989dd35bc5ff499670da34255b45b0cfd830e81f605dcf7dc5542e93ae9cd76f" |

