package com.porarri.yamabikochat.data.remote

import org.junit.Assert.assertEquals
import org.junit.Test

class RetrofitClientTest {
    @Test
    fun modelHttpClientHasNoReadOrWriteDeadline() {
        val client = RetrofitClient.createHttpClient()

        assertEquals(0, client.readTimeoutMillis)
        assertEquals(0, client.writeTimeoutMillis)
    }
}
