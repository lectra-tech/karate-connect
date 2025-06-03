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

  @ignore @createJobDescription
  Scenario: createJobDescription
  args = { namespace: "<my-namespace>", cronJobName: "<my-cron-job>", jobName: "<my-created-job-name>" }
    * def mockFile = karate.get("mockJobDescription")
    * json result = (mockFile != null ? karate.read(mockJobDescription) : karate.exec("kubectl create job "+jobName+" --namespace="+namespace+" --from=cronjob/"+cronJobName+" --dry-run=client -o 'json'"))

  @ignore @executeJob
  Scenario: executeJob
  args = { jobDescription: { ... }, jobName: "<my-created-job-name>" }
    * string jobDescriptionStr = jobDescription
    * string jobDescriptionFile = karate.write(jobDescriptionStr, ""+jobName+".json")
    * def mockFile = karate.get("mockJobDescription")
    * string result = (mockFile != null ? "job.batch/"+jobName+" created" : karate.exec("kubectl apply -f "+jobDescriptionFile))
    * match result == "job.batch/"+jobName+" created"
    * karate.exec("rm "+jobDescriptionFile)

  @ignore @waitForJobCompletion
  Scenario: waitForJobCompletion
  args = { namespace: "<my-namespace>", jobName: "<my-created-job-name>", timeoutSecondsValue: ... }
    * def mockFile = karate.get("mockJobDescription")
    * json result = (mockFile != null ? "job.batch/"+jobName+" condition met" : karate.exec("kubectl wait --for=condition=complete --timeout="+timeoutSecondsValue+"s --namespace="+namespace+" job/"+jobName))
    * match result == "job.batch/"+jobName+" condition met"

  @ignore @deleteJob
  Scenario: deleteJob
  args = { namespace: "<my-namespace>", jobName: "<my-created-job-name>" }
    * def mockFile = karate.get("mockJobDescription")
    * string result = (mockFile != null ? 'job.batch "'+jobName+'" deleted' : karate.exec("kubectl delete job --namespace="+namespace+" --field-selector metadata.name="+jobName))
    * match result == 'job.batch "'+jobName+'" deleted'

  @runJob
  Scenario: runJob
  args = { namespace: "<my-namespace>", cronJobName: "<my-cron-job>", jobName: "<my-created-job-name>", timeoutSeconds: ..., env: { "KEY1": "VALUE1", ...  }, command: [ "<cmd>" ], args: [ "arg1", "arg2", ... ] }
  example = { namespace: "foo", cronJobName: "my-cron-job", jobName: "my-job", timeoutSeconds: 60, env: { "MY_ENV1": "MY_VALUE1", "MY_ENV2": "MY_VALUE2" } }
  prerequisite: having $USER/.kube/config with rights on namespace
    # args
    * json result = { status: "WIP" }
    * def envValue = karate.get("env")
    * def commandValue = karate.get("command")
    * def argsValue = karate.get("args")
    * def timeoutSecondsValue = karate.get("timeoutSeconds", 60)
    # job description
    * karate.log("Create job "+jobName+"...")
    * json jobDescription = karate.call("@createJobDescription", ({ namespace, cronJobName, jobName })).result
    * copy existingEnv = jobDescription.spec.template.spec.containers[0].env
    * if (envValue != null) jobDescription.spec.template.spec.containers[0].env = (existingEnv != null ? existingEnv : []).concat((envValue != null ? karate.map(karate.keysOf(env), (key) => ({ "name": key, "value": env[key] })) : []))
    * if (commandValue != null) jobDescription.spec.template.spec.containers[0].command = command
    * if (argsValue != null) jobDescription.spec.template.spec.containers[0].args = args
    * result.jobDescription = jobDescription
    # execute job
    * karate.log("Execute job "+jobName+"...")
    * result.executeJobMessage = karate.call("@executeJob", ({ jobDescription, jobName })).result
    # wait for job completion
    * karate.log("Wait for job completion "+jobName+"...")
    * result.waitForJobCompletionMessage = karate.call("@waitForJobCompletion", ({ namespace, jobName, timeoutSecondsValue})).result
    # delete job
    * karate.log("Delete job "+jobName+"...")
    * result.deleteJobMessage = karate.call("@deleteJob", ({ namespace, jobName })).result
    # result
    * result.status = "OK"
