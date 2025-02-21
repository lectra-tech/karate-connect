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
Feature: cronJob

  @runJob
  Scenario: runJob
  args = { namespace: "<my-namespace>", cronJobName: "<my-cron-job>", jobName: "<my-created-job-name>", timeoutSeconds: ... }
  example = { namespace: "foo", cronJobName: "my-cron-job", jobName: "my-job", timeoutSeconds: 60 }

  prerequisite: having $USER/.kube/config with rights on namespace

    * json result = { status: "WIP" }
    * def timeoutSecondsValue = karate.get("timeoutSeconds", 60)
    * karate.log("Create job "+jobName+"...")
    When result.message = karate.exec("kubectl create job --namespace="+namespace+" --from=cronjob/"+cronJobName+" "+jobName)
    And match result.message == "job.batch/"+jobName+" created"
    * karate.log("Get status job "+jobName+"...")
    And result.message = karate.exec("kubectl wait --for=condition=complete --timeout="+timeoutSecondsValue+"s --namespace="+namespace+" job/"+jobName)
    And match result.message == "job.batch/"+jobName+" condition met"
    * karate.log("Delete job "+jobName+"...")
    And karate.exec("kubectl delete job --namespace="+namespace+" --field-selector metadata.name="+jobName)
    * result.status = "OK"


  @runJobWithEnv
  Scenario: runJobWithEnv
  args = { namespace: "<my-namespace>", cronJobName: "<my-cron-job>", jobName: "<my-created-job-name>", timeoutSeconds: ..., env: { "KEY1": "VALUE1", ...  } }
  example = { namespace: "foo", cronJobName: "my-cron-job", jobName: "my-job", timeoutSeconds: 60, env: { "MY_ENV1": "MY_VALUE1", "MY_ENV2": "MY_VALUE2" } }

  prerequisite: having $USER/.kube/config with rights on namespace

    * json result = { status: "WIP" }
    * def timeoutSecondsValue = karate.get("timeoutSeconds", 60)
    * karate.log("Create job "+jobName+"...")
    Given json jobDescription = karate.exec("kubectl create job "+jobName+" --namespace="+namespace+" --from=cronjob/"+cronJobName+" --dry-run=client -o 'json'")
    And def existingEnvs = (jobDescription.spec.template.spec.containers[0].env)
    And karate.forEach(karate.keysOf(env), function(key) { karate.appendTo(existingEnvs, ({ "name": key, "value": env[key] })); } )
    * karate.log("New envs :"+JSON.stringify(existingEnvs))
    And string jobDescriptionStr = jobDescription
    Given string jobDescriptionFile = karate.write(jobDescriptionStr, ""+jobName+".json")
    When result.message = karate.exec("kubectl apply -f "+jobDescriptionFile)
    And match result.message == "job.batch/"+jobName+" created"
    * karate.exec("rm "+jobDescriptionFile)
    * karate.log("Get status job "+jobName+"...")
    And result.message = karate.exec("kubectl wait --for=condition=complete --timeout="+timeoutSecondsValue+"s --namespace="+namespace+" job/"+jobName)
    And match result.message == "job.batch/"+jobName+" condition met"
    * karate.log("Delete job "+jobName+"...")
    And karate.exec("kubectl delete job --namespace="+namespace+" --field-selector metadata.name="+jobName)
    * result.status = "OK"
