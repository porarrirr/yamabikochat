package com.porarri.yamabikochat.pi

import com.porarri.yamabikochat.utils.DiagnosticsLogger
import com.sun.jna.Library
import com.sun.jna.Native
import kotlin.concurrent.thread

interface NodeLibrary : Library {
    fun node_start(argc: Int, argv: Array<String>): Int

    companion object {
        val INSTANCE: NodeLibrary by lazy {
            Native.load("node", NodeLibrary::class.java)
        }
    }
}

object PiNodeRunner {
    fun startEngine(arguments: List<String>) {
        thread(name = "Yamabiko Pi Agent", isDaemon = true) {
            try {
                DiagnosticsLogger.log("PiNodeRunner starting node engine with arguments=$arguments")
                val argv = arguments.toTypedArray()
                NodeLibrary.INSTANCE.node_start(argv.size, argv)
            } catch (t: Throwable) {
                DiagnosticsLogger.log("PiNodeRunner node engine exited with exception", t)
            }
        }
    }
}
