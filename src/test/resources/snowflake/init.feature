@ignore
Feature: init

  @ignore @createPem
  Scenario: createPem
    # drop existing file
    * string result = karate.write("", "private-key.pem")
    * karate.exec("rm -f "+result)
    # decode key
    * string keyBase64 = karate.properties["snowflake.privateKeyBase64"]
    * karate.log("keyBase64: "+keyBase64)
    * def key = Java.type('java.util.Base64').getDecoder().decode(keyBase64)
    * def String = Java.type('java.lang.String')
    * string keyStr = new String(key, "UTF-8")
    * karate.write(keyStr, "private-key.pem")
    * karate.properties["snowflake.privateKeyPath"] = result
