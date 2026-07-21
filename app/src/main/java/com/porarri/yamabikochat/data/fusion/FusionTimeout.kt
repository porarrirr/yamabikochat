package com.porarri.yamabikochat.data.fusion

import kotlinx.coroutines.withTimeoutOrNull

object FusionTimeout {
    class TimeoutException(val milliseconds: Int) :
        Exception("タイムアウト ($milliseconds ms)")

    suspend fun <T> run(
        milliseconds: Int,
        operation: suspend () -> T
    ): T {
        val timeoutMs = maxOf(1, milliseconds)
        return withTimeoutOrNull(timeoutMs.toLong()) {
            operation()
        } ?: throw TimeoutException(timeoutMs)
    }
}
