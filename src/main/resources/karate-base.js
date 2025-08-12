/*
 * Copyright (C) 2025 Lectra
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * SPDX-License-Identifier: Apache-2.0
 * License-Filename: LICENSE
 */
function fn() {
    karate.log("Karate Base - Lectra configuration");

    // common functions
    const uuid = () => java.util.UUID.randomUUID().toString();
    const currentTimeMillis = () => java.lang.System.currentTimeMillis();
    const offsetDateTimeNow = () => java.time.OffsetDateTime.now().toString();
    const jsonToString = (obj) => Java.type("com.intuit.karate.JsonUtils").toJson(obj, false);
    const readJsonLines = (file) => {
        const rawLines = karate.readAsString(file);
        return rawLines.split("\n").map(line => {
            const file = karate.write(line, base.random.uuid()+".json");
            const fileObject = karate.read("file:"+file);
            karate.exec("rm -f " + file);
            return (fileObject != null ? base.json.toString(fileObject) : "");
        }).join("\n");
    };
    const assertWithEpsilon = (actual, expected, epsilon) => {
        const result = java.lang.Math.abs(actual - expected) <= epsilon;
        if (!result) {
            karate.log("Assertion failed: expected " + expected + " but got " + actual + " with epsilon " + epsilon);
        }
        return result;
    };
    const hash = (algorithm, data) => {
        const digest = Java.type("java.security.MessageDigest").getInstance(algorithm);
        digest.update(data.getBytes("UTF-8"), 0, data.length);
        return Java.type("java.util.HexFormat").of().formatHex(digest.digest());
    };
    let config = {
        "base" : {
            "random": {
                "uuid": uuid
            },
            "time": {
                "currentTimeMillis": currentTimeMillis,
                "offsetDateTimeNow": offsetDateTimeNow
            },
            "json": {
                "toString": jsonToString,
                "readLines": readJsonLines
            },
            "assert": {
                "withEpsilon": assertWithEpsilon
            },
            "hash": {
                "md5": (data) => hash("MD5", data),
                "sha1": (data) => hash("SHA-1", data),
                "sha224": (data) => hash("SHA-224", data),
                "sha256": (data) => hash("SHA-256", data),
                "sha384": (data) => hash("SHA-384", data),
                "sha512": (data) => hash("SHA-512", data)
            }
        }
    };

    // lectra extensions
    const extensions = karate.properties["extensions"];
    if (extensions) {
        extensions.split(",").filter((ext) => ext !== "base").forEach(ext => {
                const extTrim = ext.trim();
                if (extTrim !== "") {
                    karate.log("Karate Base - Extension [" + extTrim + "]")
                    try {
                        config[extTrim] = karate.read("classpath:" + extTrim + "/karate-ext-config.js")();
                    } catch (exception) {
                        karate.log("Karate Base - Extension [" + extTrim + "] - Not found", exception);
                    }
                }
            }
        );
    }

    return config;
}