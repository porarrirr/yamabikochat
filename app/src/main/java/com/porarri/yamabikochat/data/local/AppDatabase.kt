package com.porarri.yamabikochat.data.local

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.TypeConverters

@Database(
    entities = [
        Conversation::class,
        ChatProject::class,
        ChatMessage::class,
        ChatMessageVariant::class,
        Settings::class,
        ChatMessageThinking::class,
        ChatMessageToolActivity::class,
        FusionTraceRecord::class,
        ModelPreset::class,
        DualChatMessage::class,
        AutoConversation::class,
        AutoConversationMessage::class,
        TokenUsageRecord::class
    ],
    version = 57,
    exportSchema = false
)
@TypeConverters(Converters::class)
abstract class AppDatabase : RoomDatabase() {

    abstract fun chatDao(): ChatDao

    companion object {
        @Volatile
        private var INSTANCE: AppDatabase? = null

        fun getDatabase(context: Context): AppDatabase {
            return INSTANCE ?: synchronized(this) {
                val instance = Room.databaseBuilder(
                    context.applicationContext,
                    AppDatabase::class.java,
                    "chat_database"
                )
                    .addMigrations(*AppDatabaseMigrations.ALL_MIGRATIONS)
                    .fallbackToDestructiveMigrationOnDowngrade()
                    .build()
                INSTANCE = instance
                instance
            }
        }
    }
}
