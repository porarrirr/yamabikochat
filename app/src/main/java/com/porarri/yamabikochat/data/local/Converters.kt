package com.porarri.yamabikochat.data.local

import androidx.room.TypeConverter
import com.google.gson.Gson

class Converters {
    @TypeConverter
    fun fromString(value: String): List<String> {
        return try {
            Gson().fromJson(value, Array<String>::class.java)?.toList() ?: emptyList()
        } catch (_: Exception) {
            emptyList()
        }
    }

    @TypeConverter
    fun fromList(list: List<String>): String {
        return Gson().toJson(list)
    }
    
    @TypeConverter
    fun fromAutoConversationStatus(status: AutoConversationStatus): String {
        return status.name
    }
    
    @TypeConverter
    fun toAutoConversationStatus(status: String): AutoConversationStatus {
        return AutoConversationStatus.valueOf(status)
    }
}
