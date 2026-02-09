package com.porarri.yamabikochat.ui.navigation

import androidx.compose.runtime.Composable
import androidx.navigation.NavType
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.navArgument

@Composable
fun NavGraph(
    navController: NavHostController,
    onMenuClick: () -> Unit = {},
    initialPrompt: String? = null,
    onInitialPromptConsumed: () -> Unit = {}
) {
    NavHost(navController = navController, startDestination = "chat/0") {
        composable(
            route = "chat/{conversationId}?focusMessageId={focusMessageId}&focusDualMessageId={focusDualMessageId}",
            arguments = listOf(
                navArgument("focusMessageId") {
                    type = NavType.StringType
                    defaultValue = ""
                },
                navArgument("focusDualMessageId") {
                    type = NavType.StringType
                    defaultValue = ""
                }
            )
        ) { backStackEntry ->
            val focusMessageId = backStackEntry.arguments
                ?.getString("focusMessageId")
                ?.takeIf { it.isNotBlank() }
                ?.toLongOrNull()
            val focusDualMessageId = backStackEntry.arguments
                ?.getString("focusDualMessageId")
                ?.takeIf { it.isNotBlank() }
                ?.toLongOrNull()
            com.porarri.yamabikochat.ui.chat.ChatScreen(
                onMenuClick = onMenuClick,
                initialPrompt = initialPrompt,
                onInitialPromptConsumed = onInitialPromptConsumed,
                focusMessageId = focusMessageId,
                focusDualMessageId = focusDualMessageId,
                onNavigateToConversation = { conversationId ->
                    navController.navigate("chat/$conversationId") {
                        popUpTo("chat/0") { inclusive = true }
                    }
                }
            )
        }
        composable("settings") {
            com.porarri.yamabikochat.ui.settings.SettingsScreen(
                onBackClick = { navController.popBackStack() }
            )
        }
    }
}
