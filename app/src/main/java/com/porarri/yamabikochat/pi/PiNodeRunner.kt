package com.porarri.yamabikochat.pi

import com.porarri.yamabikochat.utils.DiagnosticsLogger
import com.sun.jna.FunctionMapper
import com.sun.jna.Library
import com.sun.jna.Native
import kotlin.concurrent.thread

interface NodeLibrary : Library {
    fun node_start(argc: Int, argv: Array<String>): Int

    companion object {
        val INSTANCE: NodeLibrary by lazy {
            // Android's pinned NodeMobile 24.18.0-0 exports node::Start(int,
            // char**), declared in its official include/node/node.h. The
            // node_start C wrapper belongs to the iOS framework only.
            val functions = FunctionMapper { _, method ->
                check(method.name == "node_start")
                "_ZN4node5StartEiPPc"
            }
            Native.load(
                "node",
                NodeLibrary::class.java,
                mapOf(Library.OPTION_FUNCTION_MAPPER to functions)
            )
        }
    }
}

object PiNodeRunner {
    fun startEngine(arguments: List<String>) {
        thread(name = "Yamabiko Pi Agent", isDaemon = true) {
            try {
                DiagnosticsLogger.log("PiNodeRunner starting node engine")
                val argv = arguments.toTypedArray()
                NodeLibrary.INSTANCE.node_start(argv.size, argv)
            } catch (t: Throwable) {
                DiagnosticsLogger.log("PiNodeRunner node engine exited with exception", t)
            }
        }
    }
}
