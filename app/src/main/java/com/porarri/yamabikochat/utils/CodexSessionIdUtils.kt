package com.porarri.yamabikochat.utils

import java.util.UUID

object CodexSessionIdUtils {
    fun newSessionId(): String = UUID.randomUUID().toString()
}
