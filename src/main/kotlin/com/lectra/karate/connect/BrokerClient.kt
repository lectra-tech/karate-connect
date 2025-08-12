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
package com.lectra.karate.connect

import org.slf4j.LoggerFactory
import java.io.IOException

abstract class BrokerClient : AutoCloseable {
    val LOGGER = LoggerFactory.getLogger(this.javaClass)

    init {
        logExecution("Initializing ${this.javaClass.simpleName}") {
            Runtime.getRuntime().addShutdownHook(Thread {
                logExecution("Closing ${this.javaClass.simpleName}") {
                    close()
                }
            })
        }
    }

    protected fun <T> logExecution(message: String, block: () -> T): T {
        val text = "$message..."
        LOGGER.info(text)
        val result = try {
            block()
        } catch (e: IOException) {
            LOGGER.error("${text}FAILED", e.cause)
            throw e
        } catch (t: Throwable) {
            LOGGER.error("${text}FAILED", t)
            throw t
        }
        LOGGER.info("${text}DONE")
        return result
    }
}