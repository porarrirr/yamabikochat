package com.porarri.yamabikochat.data.local

import android.database.Cursor
import androidx.sqlite.db.SupportSQLiteDatabase
import io.mockk.every
import io.mockk.mockk
import io.mockk.verify
import org.junit.Assert.assertNotNull
import org.junit.Test

class AppDatabaseMigration57Test {
    @Test
    fun `migration 56 to 57 adds tool activity attachment paths`() {
        val database = mockk<SupportSQLiteDatabase>(relaxed = true)
        val cursor = mockk<Cursor>(relaxed = true)
        every { database.query("PRAGMA table_info(`chat_message_tool_activity`)") } returns cursor
        every { cursor.moveToNext() } returns false
        val migration = AppDatabaseMigrations.ALL_MIGRATIONS.firstOrNull {
            it.startVersion == 56 && it.endVersion == 57
        }
        assertNotNull(migration)

        migration!!.migrate(database)

        verify(exactly = 1) {
            database.execSQL("ALTER TABLE `chat_message_tool_activity` ADD COLUMN `attachmentPathsJSON` TEXT")
        }
        verify { cursor.close() }
    }
}
