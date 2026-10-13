package com.porarri.yamabikochat.data.local

import android.database.Cursor
import androidx.sqlite.db.SupportSQLiteDatabase
import io.mockk.every
import io.mockk.mockk
import org.junit.Assert.*
import org.junit.Test

class AppDatabaseMigration58Test {
    @Test fun removesURLColumnsAtAnyPositionAndPreservesSettingsSchemaAndValues() {
        for (legacyAtEnd in listOf(false, true)) {
            val retained = listOf("id", "defaultModel", "themeMode", "openAiCompatPresets", "selectedOpenAiCompatPreset")
            val legacy = listOf("openAiBaseUrl", "miniMaxBaseUrl")
            val names = if (legacyAtEnd) retained + legacy else listOf("id") + legacy + retained.drop(1)
            val definitions = names.map { name ->
                when (name) {
                    "id" -> "`id` INTEGER NOT NULL PRIMARY KEY"
                    "openAiBaseUrl", "miniMaxBaseUrl" -> "`$name` TEXT NOT NULL DEFAULT 'https://legacy.example/v1/'"
                    else -> "`$name` TEXT"
                }
            }
            val original = "CREATE TABLE `settings` (${definitions.joinToString(", ")})"
            val db = mockk<SupportSQLiteDatabase>(relaxed = true)
            val columnCursor = mockk<Cursor>(relaxed = true)
            var row = -1
            every { columnCursor.moveToNext() } answers { ++row < names.size }
            every { columnCursor.getColumnIndexOrThrow("name") } returns 0
            every { columnCursor.getString(0) } answers { names[row] }
            every { db.query("PRAGMA table_info(`settings`)") } returns columnCursor
            val schemaCursor = mockk<Cursor>(relaxed = true)
            every { schemaCursor.moveToFirst() } returns true
            every { schemaCursor.getString(0) } returns original
            every { db.query("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'settings'") } returns schemaCursor
            val statements = mutableListOf<String>()
            every { db.execSQL(any<String>()) } answers { statements.add(firstArg()) }
            val migration = AppDatabaseMigrations.ALL_MIGRATIONS.first { it.startVersion == 57 && it.endVersion == 58 }
            migration.migrate(db)
            assertEquals(4, statements.size)
            assertFalse(statements[0].contains("openAiBaseUrl"))
            assertFalse(statements[0].contains("miniMaxBaseUrl"))
            assertTrue(statements[0].contains("`id` INTEGER NOT NULL PRIMARY KEY"))
            retained.forEach { assertTrue(statements[0].contains("`$it`")) }
            val columns = retained.joinToString(",") { "`$it`" }
            assertEquals("INSERT INTO `settings_without_legacy` ($columns) SELECT $columns FROM `settings`", statements[1])
            assertEquals("DROP TABLE `settings`", statements[2])
            assertEquals("ALTER TABLE `settings_without_legacy` RENAME TO `settings`", statements[3])
        }
    }

    @Test fun doesNothingWhenLegacyColumnsHaveAlreadyBeenRemoved() {
        val db = mockk<SupportSQLiteDatabase>(relaxed = true)
        val cursor = mockk<Cursor>(relaxed = true)
        every { cursor.moveToNext() } returns false
        every { db.query("PRAGMA table_info(`settings`)") } returns cursor
        val statements = mutableListOf<String>()
        every { db.execSQL(any<String>()) } answers { statements.add(firstArg()) }
        AppDatabaseMigrations.ALL_MIGRATIONS.first { it.startVersion == 57 && it.endVersion == 58 }.migrate(db)
        assertTrue(statements.isEmpty())
    }
}
