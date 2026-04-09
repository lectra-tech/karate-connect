/*
 * Copyright (C) 2026 Lectra
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
package com.lectra.karate.connect.base

import java.util.concurrent.atomic.AtomicLong

class Counter(initialValue: Long = 0) {

    private val counter = AtomicLong(initialValue)

    fun incrementAndGet(): Long {
        return counter.incrementAndGet()
    }

    fun decrementAndGet(): Long {
        return counter.decrementAndGet()
    }

    fun reset() {
        counter.set(0)
    }

    fun get(): Long {
        return counter.get()
    }
}