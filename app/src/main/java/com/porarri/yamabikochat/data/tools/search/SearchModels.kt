package com.porarri.yamabikochat.data.tools.search

import com.porarri.yamabikochat.utils.DiagnosticsLogger
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import okio.Buffer
import java.net.Inet4Address
import java.net.Inet6Address
import java.net.InetAddress
import java.net.URI
import java.net.URL
import java.util.concurrent.TimeUnit
import kotlin.coroutines.coroutineContext

data class SearchResult(
    val title: String,
    val snippet: String,
    val url: String
)

interface SearchEngine {
    suspend fun search(query: String, locale: java.util.Locale, maxResults: Int): List<SearchResult>
}

data class WebToolHttpResponse(
    val body: ByteArray,
    val statusCode: Int,
    val finalUrl: String,
    val contentType: String?
)

interface WebToolHTTPClient {
    suspend fun get(url: URL, timeoutSeconds: Long): WebToolHttpResponse
}

class OkHttpWebToolHTTPClient(
    private val baseClient: OkHttpClient = OkHttpClient()
) : WebToolHTTPClient {
    companion object {
        const val MAX_RESPONSE_BYTES = 2 * 1024 * 1024
        const val USER_AGENT = "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36"
    }

    override suspend fun get(url: URL, timeoutSeconds: Long): WebToolHttpResponse {
        WebToolURLPolicy.validatePublicHTTPURL(url)
        return withContext(Dispatchers.IO) {
            val client = baseClient.newBuilder()
                .followRedirects(true)
                .followSslRedirects(true)
                .callTimeout(timeoutSeconds, TimeUnit.SECONDS)
                .connectTimeout(timeoutSeconds, TimeUnit.SECONDS)
                .readTimeout(timeoutSeconds, TimeUnit.SECONDS)
                .build()

            val request = Request.Builder()
                .url(url)
                .get()
                .header("User-Agent", USER_AGENT)
                .header(
                    "Accept",
                    "text/html,application/xhtml+xml,application/json,application/*+json,text/plain;q=0.9,*/*;q=0.1"
                )
                .build()

            val call = client.newCall(request)
            try {
                call.execute().use { response ->
                    coroutineContext.ensureActive()
                    val finalUrl = response.request.url.toString()
                    WebToolURLPolicy.validatePublicHTTPURL(URL(finalUrl))

                    val body = response.body
                        ?: throw WebToolException.ParseFailure("HTTP response body is empty")
                    val contentLength = body.contentLength()
                    if (contentLength > MAX_RESPONSE_BYTES) {
                        throw WebToolException.ParseFailure("HTTP response exceeds the 2 MB response limit")
                    }

                    val source = body.source()
                    val buffer = Buffer()
                    var total = 0L
                    while (!source.exhausted()) {
                        coroutineContext.ensureActive()
                        val read = source.read(buffer, 8_192L)
                        if (read <= 0L) break
                        total += read
                        if (total > MAX_RESPONSE_BYTES) {
                            throw WebToolException.ParseFailure("HTTP response exceeds the 2 MB response limit")
                        }
                    }

                    WebToolHttpResponse(
                        body = buffer.readByteArray(),
                        statusCode = response.code,
                        finalUrl = finalUrl,
                        contentType = response.header("Content-Type")
                    )
                }
            } catch (e: kotlinx.coroutines.CancellationException) {
                call.cancel()
                throw e
            }
        }
    }
}

object WebToolURLPolicy {
    fun validatePublicHTTPURL(url: URL) {
        val scheme = url.protocol?.lowercase()
        val host = url.host?.trim().orEmpty()
        if (scheme !in setOf("http", "https") || host.isEmpty()) {
            throw WebToolException.InvalidUrl(url.toString())
        }
        if (!url.userInfo.isNullOrEmpty()) {
            throw WebToolException.InvalidUrl("URL credentials are not allowed: $url")
        }

        val normalizedHost = host.trimStart('[').trimEnd(']').lowercase()
        if (isBlockedLocalHostname(normalizedHost)) {
            throw WebToolException.InvalidUrl("Local hostnames are not allowed: $host")
        }

        val addresses = resolvedAddresses(normalizedHost)
        if (addresses.isEmpty() || addresses.any { !it.isPubliclyRoutable }) {
            throw WebToolException.InvalidUrl("URL host is not publicly routable: $host")
        }
    }

    fun validatePublicHTTPURL(uri: URI) {
        validatePublicHTTPURL(uri.toURL())
    }

    private fun isBlockedLocalHostname(host: String): Boolean {
        return host == "localhost" ||
            host.endsWith(".localhost") ||
            host.endsWith(".local")
    }

    private fun resolvedAddresses(host: String): List<ResolvedIPAddress> {
        val inetAddresses = try {
            InetAddress.getAllByName(host)
        } catch (e: Exception) {
            DiagnosticsLogger.log("Web tool DNS resolution failed host=$host", e)
            throw WebToolException.InvalidUrl("URL host could not be resolved: $host")
        }
        return inetAddresses.mapNotNull { address ->
            when (address) {
                is Inet4Address -> {
                    val bytes = address.address
                    val value = ((bytes[0].toInt() and 0xff) shl 24) or
                        ((bytes[1].toInt() and 0xff) shl 16) or
                        ((bytes[2].toInt() and 0xff) shl 8) or
                        (bytes[3].toInt() and 0xff)
                    ResolvedIPAddress.Ipv4(value.toLong() and 0xffff_ffffL)
                }
                is Inet6Address -> ResolvedIPAddress.Ipv6(address.address.toList())
                else -> null
            }
        }
    }

    private sealed class ResolvedIPAddress {
        abstract val isPubliclyRoutable: Boolean

        data class Ipv4(val value: Long) : ResolvedIPAddress() {
            override val isPubliclyRoutable: Boolean
                get() = isPublicIPv4(value)
        }

        data class Ipv6(val bytes: List<Byte>) : ResolvedIPAddress() {
            override val isPubliclyRoutable: Boolean
                get() = isPublicIPv6(bytes)
        }

        companion object {
            fun isPublicIPv4(value: Long): Boolean {
                val first = ((value shr 24) and 0xff).toInt()
                val second = ((value shr 16) and 0xff).toInt()
                val third = ((value shr 8) and 0xff).toInt()

                if (first == 0 || first == 10 || first == 127 || first >= 224) return false
                if (first == 100 && second in 64..127) return false
                if (first == 169 && second == 254) return false
                if (first == 172 && second in 16..31) return false
                if (first == 192 && second == 168) return false
                if (first == 192 && second == 0) return false
                if (first == 198 && (second == 18 || second == 19 || second == 51)) return false
                if (first == 203 && second == 0 && third == 113) return false
                return true
            }

            fun isPublicIPv6(bytes: List<Byte>): Boolean {
                if (bytes.size != 16) return false
                val unsigned = bytes.map { it.toInt() and 0xff }
                if (unsigned.all { it == 0 }) return false
                if (unsigned.dropLast(1).all { it == 0 } && unsigned.last() == 1) return false
                if (unsigned[0] == 0xff) return false
                if ((unsigned[0] and 0xfe) == 0xfc) return false
                if (unsigned[0] == 0xfe && (unsigned[1] and 0xc0) == 0x80) return false
                if (unsigned[0] == 0x20 && unsigned[1] == 0x01 &&
                    unsigned[2] == 0x0d && unsigned[3] == 0xb8
                ) {
                    return false
                }
                mappedIPv4(unsigned)?.let { return isPublicIPv4(it) }
                return true
            }

            private fun mappedIPv4(bytes: List<Int>): Long? {
                val prefixIsMapped = bytes.take(10).all { it == 0 } &&
                    bytes[10] == 0xff &&
                    bytes[11] == 0xff
                if (!prefixIsMapped) return null
                return ((bytes[12].toLong() and 0xff) shl 24) or
                    ((bytes[13].toLong() and 0xff) shl 16) or
                    ((bytes[14].toLong() and 0xff) shl 8) or
                    (bytes[15].toLong() and 0xff)
            }
        }
    }
}
