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
@kubernetes
Feature: Test cronJob

  Scenario: nomimal
    Given string mockJobDescription = "classpath:kubernetes/job-description.json"
    When json result = kubernetes.cronJob.runJob({ namespace: "foo", cronJobName: "my-cron-job", jobName: "my-job", timeoutSeconds: 60 })
    * karate.log(result.jobDescription.spec.template.spec.containers[0])
    Then match result.status == "OK"
    And match result.jobDescription.metadata.name == "my-job"
    And match result.jobDescription.spec.template.spec.containers[0].name == "my-cron-job"
    And match result.jobDescription.spec.template.spec.containers[0].env == '#notpresent'
    And match result.jobDescription.spec.template.spec.containers[0].command == [ "ls" ]
    And match result.jobDescription.spec.template.spec.containers[0].args == [ "/tmp" ]
    And match result.executeJobMessage == "job.batch/my-job created"
    And match result.waitForJobCompletionMessage == "job.batch/my-job condition met"
    And match result.deleteJobMessage == 'job.batch "my-job" deleted'

  Scenario: withEnvCommandAndArgs
    Given string mockJobDescription = "classpath:kubernetes/job-description.json"
    When json result = kubernetes.cronJob.runJob({ namespace: "foo", cronJobName: "my-cron-job", jobName: "my-job", timeoutSeconds: 60, env: { "MY_ENV1": "MY_VALUE1", "MY_ENV2": "MY_VALUE2" }, command: [ "echo" ], args: [ "Hello", "World" ] })
    * karate.log(result.jobDescription.spec.template.spec.containers[0])
    Then match result.status == "OK"
    And match result.jobDescription.metadata.name == "my-job"
    And match result.jobDescription.spec.template.spec.containers[0].name == "my-cron-job"
    And match result.jobDescription.spec.template.spec.containers[0].env == [{"name":"MY_ENV1","value":"MY_VALUE1"},{"name":"MY_ENV2","value":"MY_VALUE2"}]
    And match result.jobDescription.spec.template.spec.containers[0].command == [ "echo" ]
    And match result.jobDescription.spec.template.spec.containers[0].args == [ "Hello", "World" ]
    And match result.executeJobMessage == "job.batch/my-job created"
    And match result.waitForJobCompletionMessage == "job.batch/my-job condition met"
    And match result.deleteJobMessage == 'job.batch "my-job" deleted'

  Scenario: completeExistingEnv
    Given string mockJobDescription = "classpath:kubernetes/job-description-with-env.json"
    When json result = kubernetes.cronJob.runJob({ namespace: "foo", cronJobName: "my-cron-job", jobName: "my-job", timeoutSeconds: 60, env: { "MY_ENV1": "MY_VALUE1", "MY_ENV2": "MY_VALUE2" }, command: [ "echo" ], args: [ "Hello", "World" ] })
    Then match result.status == "OK"
    And match result.jobDescription.spec.template.spec.containers[0].env == [{"name":"FOO","value":"BAR"},{"name":"MY_ENV1","value":"MY_VALUE1"},{"name":"MY_ENV2","value":"MY_VALUE2"}]
    And match result.jobDescription.spec.template.spec.containers[0].command == [ "echo" ]
    And match result.jobDescription.spec.template.spec.containers[0].args == [ "Hello", "World" ]
    And match result.executeJobMessage == "job.batch/my-job created"
    And match result.waitForJobCompletionMessage == "job.batch/my-job condition met"
    And match result.deleteJobMessage == 'job.batch "my-job" deleted'
