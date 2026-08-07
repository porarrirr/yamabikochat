package com.porarri.yamabikochat.ui.settings

import android.widget.Toast
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.porarri.yamabikochat.MyApplication
import com.porarri.yamabikochat.data.auth.CodexRateLimitWindow
import com.porarri.yamabikochat.data.auth.CodexUsageStatus
import com.porarri.yamabikochat.data.local.ModelPreset
import com.porarri.yamabikochat.data.local.SystemPromptPreset
import com.porarri.yamabikochat.data.remote.AlibabaCodingPlanModelCatalog
import com.porarri.yamabikochat.data.remote.ClinePassModelCatalog
import com.porarri.yamabikochat.data.remote.OpenCodeGoEndpointKind
import com.porarri.yamabikochat.data.remote.OpenCodeGoModelCatalog
import com.porarri.yamabikochat.data.remote.OpenAiCompatPreset
import com.porarri.yamabikochat.data.remote.ProviderCatalog
import com.porarri.yamabikochat.data.remote.SimpleModel
import com.porarri.yamabikochat.data.remote.ZaiCodingPlanModelCatalog
import com.porarri.yamabikochat.data.modelsdev.CatalogAvailability
import com.porarri.yamabikochat.data.modelsdev.ProviderReference
import com.porarri.yamabikochat.data.modelsdev.ModelsDevMergedProvider
import com.porarri.yamabikochat.data.modelsdev.ModelsDevProviderAdapterRegistry
import com.porarri.yamabikochat.ui.components.YamabikoOption
import com.porarri.yamabikochat.ui.components.YamabikoOptionBottomSheet
import com.porarri.yamabikochat.ui.components.YamabikoSelectRow
import com.porarri.yamabikochat.ui.components.YamabikoTextField
import com.porarri.yamabikochat.ui.preview.YamabikoPreview
import com.porarri.yamabikochat.ui.settings.components.OpenRouterModelSelector  
import com.porarri.yamabikochat.ui.settings.components.SettingsToggleRow        
import com.porarri.yamabikochat.ui.settings.sections.ModelPresetDialog
import com.porarri.yamabikochat.ui.settings.sections.ReasoningOverrideUiState   
import com.porarri.yamabikochat.ui.settings.sections.ToolingOverrideUiState
import com.porarri.yamabikochat.ui.settings.sections.ThinkingOverrideUiState
import com.porarri.yamabikochat.ui.theme.ThemeColorPreset
import com.porarri.yamabikochat.ui.settings.sections.autoConversationSettingsSection
import com.porarri.yamabikochat.ui.settings.sections.diagnosticsSection
import com.porarri.yamabikochat.ui.settings.sections.dualModeSettingsSection
import com.porarri.yamabikochat.ui.settings.sections.fusionModeSettingsSection
import com.porarri.yamabikochat.ui.settings.sections.geminiThinkingInfoSection
import com.porarri.yamabikochat.ui.settings.sections.mathRenderingSettingsSection
import com.porarri.yamabikochat.ui.settings.sections.modelPresetsSection
import com.porarri.yamabikochat.ui.settings.sections.openRouterAdvancedSettingsSection
import com.porarri.yamabikochat.ui.settings.sections.openRouterReasoningSection
import com.porarri.yamabikochat.R
import com.porarri.yamabikochat.utils.MiniMaxUtils
import com.porarri.yamabikochat.utils.ModelUtils
import com.porarri.yamabikochat.utils.CodexModelPresets
import com.porarri.yamabikochat.utils.CodexUserAgentUtils
import kotlin.math.roundToInt
import androidx.compose.material3.TextButton
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.launch
import java.time.Instant
import java.util.Locale

private enum class SettingsSheet {
    ThemeColor,
    ThemeMode,
    ApiProvider,
    SystemPromptPreset,
    OpenAiCompatPreset,
    ThinkingLevel,
    CodexModel,
    SuperGrokModel,
    SuperGrokReasoningEffort,
    CodexReasoningEffort,
    CodexReasoningSummary,
    CodexVerbosity,
    CodexWebSearchContextSize,
    CodexUserAgent
}

private const val SYSTEM_PROMPT_PRESET_KEY_NEW = "\u0000SYSTEM_PROMPT_NEW"
private const val SYSTEM_PROMPT_PRESET_LABEL_NEW = "＋ 新規作成"

@OptIn(ExperimentalMaterial3Api::class, FlowPreview::class)
@Composable
fun SettingsScreen(
    onBackClick: () -> Unit = {},
    viewModel: SettingsViewModel = viewModel(
        factory = (LocalContext.current.applicationContext as MyApplication).viewModelFactory
    )
) {
    val context = LocalContext.current
    val settings by viewModel.settings.collectAsState()
    val apiKeyStatus by viewModel.apiKeyStatus.collectAsState()
    val presets by viewModel.modelPresets.collectAsState()
    val openRouterModelsState by viewModel.openRouterModels.collectAsState()
    val openRouterModelsLoadingState by viewModel.openRouterModelsLoading.collectAsState()
    val openRouterModelsErrorState by viewModel.openRouterModelsError.collectAsState()
    val modelsDevCatalogState by viewModel.modelsDevCatalogState.collectAsState()
    val secureStorageError by viewModel.secureStorageError.collectAsState()
    val codexAuthState by viewModel.codexAuthState.collectAsState()
    val codexAuthError by viewModel.codexAuthError.collectAsState()
    val superGrokAuthState by viewModel.superGrokAuthState.collectAsState()
    val superGrokAuthError by viewModel.superGrokAuthError.collectAsState()
    val superGrokAuthActionRunning by viewModel.superGrokAuthActionRunning.collectAsState()
    val codexUsageState by viewModel.codexUsageState.collectAsState()
    val tokenUsageState by viewModel.tokenUsageState.collectAsState()

    LaunchedEffect(secureStorageError) {
        secureStorageError?.let {
            Toast.makeText(context, it, Toast.LENGTH_LONG).show()
            viewModel.clearSecureStorageError()
        }
    }

    LaunchedEffect(codexAuthError) {
        codexAuthError?.let {
            Toast.makeText(context, it, Toast.LENGTH_LONG).show()
            viewModel.clearCodexAuthError()
        }
    }

    LaunchedEffect(superGrokAuthError) {
        superGrokAuthError?.let {
            Toast.makeText(context, it, Toast.LENGTH_LONG).show()
            viewModel.clearSuperGrokAuthError()
        }
    }

    val state = rememberSettingsScreenState(
        viewModel = viewModel,
        settings = settings,
        openRouterModels = openRouterModelsState,
        openRouterModelsLoading = openRouterModelsLoadingState,
        openRouterModelsError = openRouterModelsErrorState,
        modelsDevCatalogState = modelsDevCatalogState
    )
    val coroutineScope = rememberCoroutineScope()

    LaunchedEffect(state) {
        snapshotFlow { state.buildUpdateRequest() }
            .drop(1)
            .debounce(500)
            .distinctUntilChanged()
            .collectLatest { request ->
                viewModel.saveSettings(request)
            }
    }

    DisposableEffect(state) {
        onDispose {
            viewModel.saveSettings(state.buildUpdateRequest())
        }
    }

    with(state) {
        val dualReasoningStateA = dualReasoningStateA()
        val dualReasoningStateB = dualReasoningStateB()
        val autoReasoningStateA = autoReasoningStateA()
        val autoReasoningStateB = autoReasoningStateB()
        val dualToolsStateA = dualToolsStateA()
        val dualToolsStateB = dualToolsStateB()
        val autoToolsStateA = autoToolsStateA()
        val autoToolsStateB = autoToolsStateB()
        val dualThinkingStateA = dualThinkingStateA()
        val dualThinkingStateB = dualThinkingStateB()
        val autoThinkingStateA = autoThinkingStateA()
        val autoThinkingStateB = autoThinkingStateB()
        val presetDialogState = buildPresetDialogState()
        val isCurrentModelFree = isCurrentModelFree()
        var geminiAdvancedExpanded by remember { mutableStateOf(false) }        
        var showAdvancedSettings by rememberSaveable { mutableStateOf(false) }
        val globalPresets = settings?.buildGlobalProviderPresets().orEmpty()    
        val globalPresetsInChat = globalPresets.filter { preset ->
            val providerKey = preset.apiProvider.uppercase()
            showGlobalProviderPresetsInChatByProvider[providerKey] ?: showGlobalProviderPresetsInChat
        }
        val presetOptions = globalPresets + presets
        val existingProviderKeys = ProviderCatalog.options.map { it.key }.toSet()
        val modelsDevProviderOptions = modelsDevCatalogState.providers
            .filterNot { provider ->
                provider.id in setOf("openrouter", "google", "openai", "opencode", "cline-pass", "alibaba-coding-plan", "zai", "minimax")
            }
            .map { provider ->
                YamabikoOption(
                    key = provider.reference.persistedId,
                    title = provider.name,
                    subtitle = provider.id
                )
            }
        val allProviderOptions = ProviderCatalog.options.map {
            YamabikoOption(key = it.key, title = it.title)
        } + modelsDevProviderOptions.filterNot { it.key in existingProviderKeys }

        ModelPresetDialog(
            state = presetDialogState,
            onDismiss = { showPresetDialog = false },
            onConfirm = { onPresetConfirm() },
            systemPromptPresets = systemPromptPresetsLocal,
            openAiCompatPresets = openAiCompatPresetsLocal,
            openRouterModels = openRouterModels,
            openRouterModelsLoading = openRouterModelsLoading,
            openRouterModelsError = openRouterModelsError,
            onRefreshOpenRouterModels = { viewModel.refreshOpenRouterModels() },
            pinnedModelIds = openRouterPinnedModels,
            recentModelIds = openRouterRecentModels,
            onTogglePinned = { toggleOpenRouterPinnedModel(it) },
            onRecentUsed = { registerOpenRouterRecentModel(it) }
        )

        var selectedTab by rememberSaveable { mutableStateOf(0) }
        val tabs = listOf(
            stringResource(R.string.settings_tab_api),
            stringResource(R.string.settings_tab_system_prompt),
            stringResource(R.string.settings_tab_dual_auto_math),
            stringResource(R.string.settings_tab_appearance)
        )
        var activeSheet by remember { mutableStateOf<SettingsSheet?>(null) }

        activeSheet?.let { sheet ->
            when (sheet) {
                SettingsSheet.ThemeColor -> {
                    val options = buildList {
                        ThemeColorPreset.entries.forEach { preset ->
                            add(YamabikoOption(key = preset.key, title = preset.label))
                        }
                        add(
                            YamabikoOption(
                                key = ThemeColorPreset.KEY_DYNAMIC,
                                title = stringResource(R.string.dynamic_color_title),
                                subtitle = stringResource(R.string.dynamic_color_subtitle)
                            )
                        )
                    }
                    val selectedKey =
                        if (dynamicColorEnabled) ThemeColorPreset.KEY_DYNAMIC else themeColor
                    YamabikoOptionBottomSheet(
                        title = stringResource(R.string.appearance_color_title),
                        options = options,
                        selectedKey = selectedKey,
                        onOptionSelected = { option ->
                            if (option.key == ThemeColorPreset.KEY_DYNAMIC) {
                                dynamicColorEnabled = true
                            } else {
                                dynamicColorEnabled = false
                                themeColor = option.key
                            }
                        },
                        onDismissRequest = { activeSheet = null }
                    )
                }

                SettingsSheet.ThemeMode -> {
                    YamabikoOptionBottomSheet(
                        title = stringResource(R.string.theme_title),
                        options = listOf(
                            YamabikoOption(key = "SYSTEM", title = stringResource(R.string.theme_follow_system)),
                            YamabikoOption(key = "LIGHT", title = stringResource(R.string.theme_light)),
                            YamabikoOption(key = "DARK", title = stringResource(R.string.theme_dark))
                        ),
                        selectedKey = themeMode,
                        onOptionSelected = { themeMode = it.key },
                        onDismissRequest = { activeSheet = null }
                    )
                }

                SettingsSheet.ApiProvider -> {
                    YamabikoOptionBottomSheet(
                        title = "API Provider",
                        options = allProviderOptions,
                        selectedKey = apiProvider,
                        onOptionSelected = { switchApiProvider(it.key) },
                        onDismissRequest = { activeSheet = null },
                        searchable = true,
                        searchPlaceholder = "プロバイダーを検索"
                    )
                }

                SettingsSheet.SystemPromptPreset -> {
                    val options = buildList {
                        add(
                            YamabikoOption(
                                key = SYSTEM_PROMPT_PRESET_KEY_NEW,
                                title = SYSTEM_PROMPT_PRESET_LABEL_NEW,
                                subtitle = "空のプロンプトから作成"
                            )
                        )
                        systemPromptPresetsLocal.forEach { preset ->
                            val summary = preset.prompt
                                .lineSequence()
                                .firstOrNull()
                                ?.trim()
                                .orEmpty()
                                .take(80)
                                .takeIf { it.isNotBlank() }
                            add(
                                YamabikoOption(
                                    key = preset.name,
                                    title = preset.name,
                                    subtitle = summary
                                )
                            )
                        }
                    }
                    val selectedKey = selectedSystemPromptPresetLocal
                    YamabikoOptionBottomSheet(
                        title = "System Prompt Preset",
                        options = options,
                        selectedKey = selectedKey,
                        onOptionSelected = { option ->
                            when (option.key) {
                                SYSTEM_PROMPT_PRESET_KEY_NEW -> {
                                    selectedSystemPromptPresetLocal = null
                                    systemPromptPresetName = ""
                                    systemPrompt = ""
                                    return@YamabikoOptionBottomSheet
                                }
                            }

                            val preset = systemPromptPresetsLocal.firstOrNull { it.name == option.key }
                                ?: return@YamabikoOptionBottomSheet      

                            selectedSystemPromptPresetLocal = preset.name
                            systemPromptPresetName = preset.name
                            systemPrompt = preset.prompt
                        },
                        onDismissRequest = { activeSheet = null }
                    )
                }

                SettingsSheet.OpenAiCompatPreset -> {
                    if (openAiCompatPresetsLocal.isEmpty()) {
                        activeSheet = null
                        return@let
                    }
                    YamabikoOptionBottomSheet(
                        title = "OpenAI (Custom) Preset",
                        options = openAiCompatPresetsLocal.map { preset ->
                            YamabikoOption(
                                key = preset.name,
                                title = preset.name,
                                subtitle = preset.baseUrl
                            )
                        },
                        selectedKey = selectedOpenAiCompatPresetLocal,
                        onOptionSelected = { option ->
                            val preset = openAiCompatPresetsLocal.firstOrNull { it.name == option.key }
                                ?: return@YamabikoOptionBottomSheet

                            selectedOpenAiCompatPresetLocal = preset.name
                            compatPresetName = preset.name
                            compatPresetBaseUrl = preset.baseUrl
                            viewModel.selectOpenAiCompatPreset(preset.name)

                            openAiCompatApiKeyInput = ""
                            openAiCompatKeyDirty = false
                            openAiCompatKeyVisible = false
                            openAiCompatKeyLoadedFromStorage = false
                        },
                        onDismissRequest = { activeSheet = null }
                    )
                }

                SettingsSheet.SuperGrokModel -> {
                    val options = com.porarri.yamabikochat.data.remote.SuperGrokModelCatalog.supportedModels.map { modelOption ->
                        YamabikoOption(
                            key = modelOption.id,
                            title = modelOption.displayName,
                            subtitle = modelOption.description
                        )
                    }
                    YamabikoOptionBottomSheet(
                        title = "SuperGrok Model",
                        options = options,
                        selectedKey = model,
                        onOptionSelected = { option ->
                            model = option.key
                            val selected = com.porarri.yamabikochat.data.remote.SuperGrokModelCatalog.modelFor(option.key)
                            if (selected?.supportsReasoning == false) {
                                superGrokReasoningEnabled = false
                            } else if (superGrokReasoningEffort.isBlank()) {
                                superGrokReasoningEffort = "medium"
                            }
                        },
                        onDismissRequest = { activeSheet = null }
                    )
                }

                SettingsSheet.SuperGrokReasoningEffort -> {
                    val options = listOf(
                        YamabikoOption(key = "low", title = "low"),
                        YamabikoOption(key = "medium", title = "medium"),
                        YamabikoOption(key = "high", title = "high")
                    )
                    YamabikoOptionBottomSheet(
                        title = "Reasoning Effort",
                        options = options,
                        selectedKey = superGrokReasoningEffort,
                        onOptionSelected = { option -> superGrokReasoningEffort = option.key },
                        onDismissRequest = { activeSheet = null }
                    )
                }

                SettingsSheet.CodexModel -> {
                    val presets = CodexModelPresets.visiblePresets()
                    val options = presets.map { preset ->
                        YamabikoOption(
                            key = preset.model,
                            title = preset.displayName,
                            subtitle = preset.description
                        )
                    }
                    YamabikoOptionBottomSheet(
                        title = "Codex Model",
                        options = options,
                        selectedKey = model,
                        onOptionSelected = { option ->
                            model = option.key
                            val selectedPreset = CodexModelPresets.findPreset(option.key)
                            val supported = selectedPreset?.supportedReasoningEfforts?.map { it.effort }.orEmpty()
                            val defaultEffort = selectedPreset?.defaultReasoningEffort ?: "medium"
                            if (supported.isNotEmpty() && !supported.contains(codexReasoningEffort)) {
                                codexReasoningEffort = defaultEffort
                            } else if (codexReasoningEffort.isBlank()) {
                                codexReasoningEffort = defaultEffort
                            }
                        },
                        onDismissRequest = { activeSheet = null }
                    )
                }

                SettingsSheet.CodexReasoningEffort -> {
                    val preset = CodexModelPresets.findPreset(model)
                    val options = preset?.supportedReasoningEfforts?.map {
                        YamabikoOption(key = it.effort, title = it.effort, subtitle = it.description)
                    } ?: listOf(
                        YamabikoOption(key = "low", title = "low"),
                        YamabikoOption(key = "medium", title = "medium"),
                        YamabikoOption(key = "high", title = "high")
                    )
                    YamabikoOptionBottomSheet(
                        title = "Reasoning Effort",
                        options = options,
                        selectedKey = codexReasoningEffort,
                        onOptionSelected = { codexReasoningEffort = it.key },
                        onDismissRequest = { activeSheet = null }
                    )
                }

                SettingsSheet.CodexReasoningSummary -> {
                    val options = listOf(
                        YamabikoOption(
                            key = "auto",
                            title = "auto",
                            subtitle = "Model decides summary detail"
                        ),
                        YamabikoOption(
                            key = "concise",
                            title = "concise",
                            subtitle = "Short, high-level summary"
                        ),
                        YamabikoOption(
                            key = "detailed",
                            title = "detailed",
                            subtitle = "Longer, more detailed summary"
                        ),
                        YamabikoOption(
                            key = "none",
                            title = "none",
                            subtitle = "Do not request a summary"
                        )
                    )
                    val selectedKey = codexReasoningSummary.ifBlank { "auto" }
                    YamabikoOptionBottomSheet(
                        title = "Reasoning Summary",
                        options = options,
                        selectedKey = selectedKey,
                        onOptionSelected = { codexReasoningSummary = it.key },
                        onDismissRequest = { activeSheet = null }
                    )
                }

                SettingsSheet.CodexVerbosity -> {
                    val options = listOf(
                        YamabikoOption(
                            key = "low",
                            title = "low",
                            subtitle = "Shorter responses"
                        ),
                        YamabikoOption(
                            key = "medium",
                            title = "medium",
                            subtitle = "Balanced responses"
                        ),
                        YamabikoOption(
                            key = "high",
                            title = "high",
                            subtitle = "More verbose responses"
                        )
                    )
                    val selectedKey = codexVerbosity.ifBlank { "medium" }
                    YamabikoOptionBottomSheet(
                        title = "Verbosity",
                        options = options,
                        selectedKey = selectedKey,
                        onOptionSelected = { codexVerbosity = it.key },
                        onDismissRequest = { activeSheet = null }
                    )
                }

                SettingsSheet.CodexWebSearchContextSize -> {
                    val options = listOf(
                        YamabikoOption(
                            key = "low",
                            title = "low",
                            subtitle = "Smaller search context"
                        ),
                        YamabikoOption(
                            key = "medium",
                            title = "medium",
                            subtitle = "Balanced search context"
                        ),
                        YamabikoOption(
                            key = "high",
                            title = "high",
                            subtitle = "Larger search context"
                        )
                    )
                    val selectedKey = codexWebSearchContextSize.ifBlank { "medium" }
                    YamabikoOptionBottomSheet(
                        title = "Web Search Context",
                        options = options,
                        selectedKey = selectedKey,
                        onOptionSelected = { codexWebSearchContextSize = it.key },
                        onDismissRequest = { activeSheet = null }
                    )
                }

                SettingsSheet.CodexUserAgent -> {
                    val options = listOf(
                        YamabikoOption(
                            key = CodexUserAgentUtils.PRESET_ANDROID,
                            title = "Android (default)",
                            subtitle = "App User-Agent"
                        ),
                        YamabikoOption(
                            key = CodexUserAgentUtils.PRESET_UBUNTU,
                            title = "Ubuntu"
                        ),
                        YamabikoOption(
                            key = CodexUserAgentUtils.PRESET_WINDOWS_POWERSHELL,
                            title = "Windows PowerShell"
                        ),
                        YamabikoOption(
                            key = CodexUserAgentUtils.PRESET_WINDOWS_CMD,
                            title = "Windows Command Prompt"
                        )
                    )
                    val selectedKey = codexUserAgentPreset.ifBlank { CodexUserAgentUtils.PRESET_ANDROID }
                    YamabikoOptionBottomSheet(
                        title = "User-Agent Preset",
                        options = options,
                        selectedKey = selectedKey,
                        onOptionSelected = { codexUserAgentPreset = it.key },
                        onDismissRequest = { activeSheet = null }
                    )
                }

                SettingsSheet.ThinkingLevel -> {
                    if (apiProvider != "GEMINI" || !ModelUtils.isThinkingLevelSupported(model)) {
                        activeSheet = null
                        return@let
                    }
                    val options = ModelUtils.getThinkingLevelOptions(model)
                    val selectedKey =
                        ModelUtils.normalizeThinkingLevel(model, thinkingLevel)
                            ?: ModelUtils.getDefaultThinkingLevel(model)
                    YamabikoOptionBottomSheet(
                        title = "Thinking Level",
                        options = options.map { level ->
                            YamabikoOption(
                                key = level,
                                title = when (level) {
                                    "minimal" -> "Minimal (ほぼOFF)"
                                    "low" -> "Low"
                                    "medium" -> "Medium"
                                    else -> "\u30B7\u30B9\u30C6\u30E0\u306B\u5F93\u3046"
                                }
                            )
                        },
                        selectedKey = selectedKey,
                        onOptionSelected = { thinkingLevel = it.key },
                        onDismissRequest = { activeSheet = null }
                    )
                }
            }
        }
        Scaffold(
            topBar = {
                TopAppBar(
                    title = { Text("設定") },
                    navigationIcon = {
                        IconButton(
                            onClick = {
                                if (showAdvancedSettings) {
                                    showAdvancedSettings = false
                                } else {
                                    onBackClick()
                                }
                            }
                        ) {
                            Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                        }
                    }
                )
            },
            containerColor = MaterialTheme.colorScheme.surfaceVariant
        ) { padding ->
            if (!showAdvancedSettings) {
                SettingsHomeContent(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding)
                        .padding(horizontal = 16.dp, vertical = 16.dp),
                    onOpenTab = { tabIndex ->
                        selectedTab = tabIndex
                        showAdvancedSettings = true
                    }
                )
            } else {
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding)
                        .padding(horizontal = 16.dp, vertical = 16.dp)
                ) {
            Text(
                "変更は自動で保存されます。",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Spacer(modifier = Modifier.height(8.dp))
            ScrollableTabRow(selectedTabIndex = selectedTab, edgePadding = 0.dp) {
                tabs.forEachIndexed { index, title ->
                    Tab(
                        selected = selectedTab == index,
                        onClick = { selectedTab = index },
                        text = { Text(title) }
                    )
                }
            }
            Spacer(modifier = Modifier.height(12.dp))
            LazyColumn(
                modifier = Modifier
                    .fillMaxWidth()
                    .weight(1f),
                verticalArrangement = Arrangement.spacedBy(24.dp)
            ) {
                if (selectedTab == 0 || selectedTab == 1 || selectedTab == 2 || selectedTab == 3) {
                    if (selectedTab == 3) {
                        item {
                            Card(
                                modifier = Modifier.fillMaxWidth(),
                                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
                                border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.6f)),
                                elevation = CardDefaults.cardElevation(defaultElevation = 1.dp)
                            ) {
                                Column(
                                    modifier = Modifier.padding(16.dp),
                                    verticalArrangement = Arrangement.spacedBy(16.dp)
                                ) {
                                    Text(
                                        text = stringResource(R.string.appearance_section_title),
                                        style = MaterialTheme.typography.titleMedium,
                                        fontWeight = FontWeight.SemiBold
                                    )
                                    Text(
                                        text = stringResource(R.string.appearance_description),
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                    val themeColorLabel =
                                        if (dynamicColorEnabled) "Dynamic Color" else ThemeColorPreset.fromKey(themeColor).label
                                    YamabikoSelectRow(
                                        title = stringResource(R.string.appearance_color_title),
                                        value = themeColorLabel,
                                        onClick = { activeSheet = SettingsSheet.ThemeColor },
                                        leadingContent = { Icon(Icons.Default.Palette, contentDescription = null) }
                                    )
                                    val themeLabel = when (themeMode) {
                                        "LIGHT" -> stringResource(R.string.theme_light)
                                        "DARK" -> stringResource(R.string.theme_dark)
                                        else -> stringResource(R.string.theme_follow_system)
                                    }
                                    YamabikoSelectRow(
                                        title = stringResource(R.string.theme_title),
                                        value = themeLabel,
                                        onClick = { activeSheet = SettingsSheet.ThemeMode }
                                    )
                                }
                            }
                        }
                        mathRenderingSettingsSection(
                            mathRenderingEnabled = mathRenderingEnabled,
                            onMathRenderingChange = {
                                mathRenderingEnabled = it
                                // 即時反映: DBへ保存してChat表示にリアルタイムで流す
                                viewModel.updateMathRenderingEnabled(it)
                            }
                        )
                    }
                    if (selectedTab == 0) {
                        if (apiProvider == "CODEX_AUTH") {
                            item {
                                Card(
                                    modifier = Modifier.fillMaxWidth(),
                                    colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
                                    border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.6f)),
                                    elevation = CardDefaults.cardElevation(defaultElevation = 1.dp)
                                ) {
                                    Column(
                                        modifier = Modifier.padding(16.dp),
                                        verticalArrangement = Arrangement.spacedBy(16.dp)
                                    ) {
                                        Text(
                                            text = "Codex Auth",
                                            style = MaterialTheme.typography.titleMedium,
                                            fontWeight = FontWeight.SemiBold
                                        )
                                        val statusText = if (codexAuthState.isLoggedIn) "Signed in" else "Not signed in"
                                        Text(
                                            text = statusText,
                                            style = MaterialTheme.typography.bodyLarge,
                                            fontWeight = FontWeight.SemiBold,
                                            color = MaterialTheme.colorScheme.onSurface
                                        )
                                        codexAuthState.email?.let {
                                            LabeledValueBlock(label = "Email", value = it)
                                        }
                                        codexAuthState.planType?.let {
                                            LabeledValueBlock(label = "Plan", value = it)
                                        }
                                        codexAuthState.accountId?.let {
                                            LabeledValueBlock(label = "Workspace", value = it)
                                        }
                                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                            FilledTonalButton(onClick = { viewModel.loginCodexAuth() }) { Text("Sign in") }
                                            TextButton(onClick = { viewModel.refreshCodexAuth(force = true) }) { Text("Refresh") }
                                            TextButton(onClick = { viewModel.logoutCodexAuth() }) { Text("Sign out") }
                                        }
                                        Text(
                                            text = if (codexAuthState.hasApiKey) "API key ready" else "API key not available yet",
                                            style = MaterialTheme.typography.bodyMedium,
                                            fontWeight = FontWeight.Medium,
                                            color = MaterialTheme.colorScheme.onSurface
                                        )
                                        val uaLabel = when (codexUserAgentPreset.uppercase()) {
                                            CodexUserAgentUtils.PRESET_UBUNTU -> "Ubuntu"
                                            CodexUserAgentUtils.PRESET_WINDOWS_POWERSHELL -> "Windows PowerShell"
                                            CodexUserAgentUtils.PRESET_WINDOWS_CMD -> "Windows Command Prompt"
                                            else -> "Android (default)"
                                        }
                                        YamabikoSelectRow(
                                            title = "User-Agent",
                                            value = uaLabel,
                                            onClick = { activeSheet = SettingsSheet.CodexUserAgent },
                                            leadingContent = { Icon(Icons.Default.Computer, contentDescription = null) }
                                        )

                                        Spacer(modifier = Modifier.height(4.dp))

                                        Text(
                                            text = "Rate limits",
                                            style = MaterialTheme.typography.titleSmall,
                                            fontWeight = FontWeight.SemiBold
                                        )
                                        val canCheckUsage = codexAuthState.isLoggedIn &&
                                            !codexAuthState.accountId.isNullOrBlank()
                                        Row(
                                            verticalAlignment = Alignment.CenterVertically,
                                            horizontalArrangement = Arrangement.spacedBy(8.dp)
                                        ) {
                                            TextButton(
                                                onClick = { viewModel.refreshCodexUsage() },
                                                enabled = canCheckUsage && !codexUsageState.isLoading
                                            ) { Text("Check /status") }
                                            if (codexUsageState.isLoading) {
                                                CircularProgressIndicator(
                                                    modifier = Modifier.size(18.dp),
                                                    strokeWidth = 2.dp
                                                )
                                            }
                                        }
                                        if (!codexAuthState.isLoggedIn) {
                                            Text(
                                                text = "Sign in to check rate limits.",
                                                style = MaterialTheme.typography.bodySmall,
                                                color = MaterialTheme.colorScheme.onSurfaceVariant
                                            )
                                        } else if (codexAuthState.accountId.isNullOrBlank()) {
                                            Text(
                                                text = "Workspace/account ID is required to check rate limits.",
                                                style = MaterialTheme.typography.bodySmall,
                                                color = MaterialTheme.colorScheme.onSurfaceVariant
                                            )
                                        }
                                        codexUsageState.error?.let { err ->
                                            Text(
                                                text = err,
                                                style = MaterialTheme.typography.bodySmall,
                                                color = MaterialTheme.colorScheme.error
                                            )
                                        }
                                        codexUsageState.lastUpdated?.let { timestamp ->
                                            Text(
                                                text = "Updated: $timestamp",
                                                style = MaterialTheme.typography.bodySmall,
                                                color = MaterialTheme.colorScheme.onSurfaceVariant
                                            )
                                        }
                                        codexUsageState.usage?.let { usage ->
                                            codexUsagePlanLabel(usage)?.let {
                                                LabeledValueBlock(label = "Plan (/status)", value = it)
                                            }
                                            usage.primaryWindow?.let { window ->
                                                LabeledValueBlock(
                                                    label = "Primary limit",
                                                    value = formatCodexRateLimitWindow(window)
                                                )
                                            }
                                            usage.secondaryWindow?.let { window ->
                                                LabeledValueBlock(
                                                    label = "Secondary limit",
                                                    value = formatCodexRateLimitWindow(window)
                                                )
                                            }
                                            codexUsageCreditsLabel(usage)?.let {
                                                LabeledValueBlock(label = "Credits", value = it)
                                            }
                                        }
                                        val hasCodexUsageData = codexUsageState.usage?.let { usage ->
                                            usage.primaryWindow != null ||
                                                usage.secondaryWindow != null ||
                                                usage.credits != null ||
                                                !usage.planType.isNullOrBlank()
                                        } == true
                                        if (!codexUsageState.isLoading &&
                                            codexUsageState.error == null &&
                                            canCheckUsage &&
                                            codexUsageState.lastUpdated != null &&
                                            !hasCodexUsageData
                                        ) {
                                            Text(
                                                text = "No rate limit data returned.",
                                                style = MaterialTheme.typography.bodySmall,
                                                color = MaterialTheme.colorScheme.onSurfaceVariant
                                            )
                                        }
                                    }
                                }
                            }
                        }
                        if (apiProvider == "SUPERGROK") {
                            item {
                                Card(
                                    modifier = Modifier.fillMaxWidth(),
                                    colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
                                    border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.6f)),
                                    elevation = CardDefaults.cardElevation(defaultElevation = 1.dp)
                                ) {
                                    Column(
                                        modifier = Modifier.padding(16.dp),
                                        verticalArrangement = Arrangement.spacedBy(16.dp)
                                    ) {
                                        Text(
                                            text = "SuperGrok Auth",
                                            style = MaterialTheme.typography.titleMedium,
                                            fontWeight = FontWeight.SemiBold
                                        )
                                        Text(
                                            text = if (superGrokAuthState.isLoggedIn) "Signed in" else "Not signed in",
                                            style = MaterialTheme.typography.bodyLarge,
                                            fontWeight = FontWeight.SemiBold
                                        )
                                        superGrokAuthState.email?.let {
                                            LabeledValueBlock(label = "Email", value = it)
                                        }
                                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                            FilledTonalButton(
                                                onClick = { viewModel.loginSuperGrokWithBrowser() },
                                                enabled = !superGrokAuthActionRunning
                                            ) {
                                                Text("Sign in (Browser)")
                                            }
                                            TextButton(
                                                onClick = { viewModel.loginSuperGrokWithDeviceCode() },
                                                enabled = !superGrokAuthActionRunning
                                            ) {
                                                Text("Device Code")
                                            }
                                        }
                                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                            TextButton(
                                                onClick = { viewModel.refreshSuperGrok(force = true) },
                                                enabled = !superGrokAuthActionRunning
                                            ) {
                                                Text("Refresh")
                                            }
                                            TextButton(
                                                onClick = { viewModel.logoutSuperGrok() },
                                                enabled = !superGrokAuthActionRunning
                                            ) {
                                                Text("Sign out")
                                            }
                                        }
                                        if (superGrokAuthActionRunning) {
                                            Text(
                                                text = "SuperGrok認証処理中...",
                                                style = MaterialTheme.typography.bodySmall,
                                                color = MaterialTheme.colorScheme.onSurfaceVariant
                                            )
                                        }
                                        superGrokAuthState.pendingDeviceCode?.let { challenge ->
                                            Text(
                                                text = "Verification URL: ${challenge.browserUrl}",
                                                style = MaterialTheme.typography.bodySmall,
                                                color = MaterialTheme.colorScheme.onSurfaceVariant
                                            )
                                            Text(
                                                text = "User code: ${challenge.userCode}",
                                                style = MaterialTheme.typography.bodySmall,
                                                color = MaterialTheme.colorScheme.onSurfaceVariant
                                            )
                                        }
                                        Text(
                                            text = "Connect to xAI API using SuperGrok / X Premium+ OAuth tokens.",
                                            style = MaterialTheme.typography.bodySmall,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant
                                        )
                                        Text(
                                            text = "Browser ログインは ${com.porarri.yamabikochat.data.auth.SuperGrokAuthConstants.REDIRECT_URI} を使います。OpenCode / Grok CLI と同時起動するとポートが競合します。",
                                            style = MaterialTheme.typography.bodySmall,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant
                                        )
                                    }
                                }
                            }
                        }
                        item {
                            TokenUsageStatsCard(state = tokenUsageState)
                        }
        item {
            Card(
                modifier = Modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
                border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.6f)),
                elevation = CardDefaults.cardElevation(defaultElevation = 1.dp)
            ) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(16.dp)
                ) {
                    Text(
                        text = "APIプロバイダー",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold
                    )
                    val providerLabel = modelsDevCatalogState.providers.firstOrNull {
                        it.id == ProviderReference(apiProvider).modelsDevId
                    }?.name ?: ProviderCatalog.displayName(apiProvider)
                    YamabikoSelectRow(
                        title = "API Provider",
                        value = providerLabel,
                        onClick = { activeSheet = SettingsSheet.ApiProvider }
                    )
                }
            }
        }

        if (apiProvider != "CODEX_AUTH" && apiProvider != "SUPERGROK") {
            item {
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
                    border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.6f)),
                    elevation = CardDefaults.cardElevation(defaultElevation = 1.dp)
                ) {
                    Column(
                        modifier = Modifier.padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(16.dp)
                    ) {
                        Text(
                            text = "APIキー",
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.SemiBold
                        )
                        Text(
                            text = "APIキーは端末内の暗号化ストレージに保存されます。",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        val isGeminiProvider = apiProvider == "GEMINI"
                        val isOpenRouterProvider = apiProvider == "OPENROUTER"
                        val isOpenAiProvider = apiProvider == "OPENAI"
                        val isMiniMaxProvider = apiProvider == "MINIMAX"
                        val isOpenAiCompatProvider = apiProvider == "OPENAI_COMPAT"
                        val isZaiProvider = apiProvider == "ZAI"
                        val isOpenCodeGoProvider = apiProvider == "OPENCODE_GO"
                        val isClinePassProvider = apiProvider == "CLINEPASS"
                        val isAlibabaCodingPlanProvider = apiProvider == "ALIBABA_CODING_PLAN"
                        val selectedCompatPreset = selectedOpenAiCompatPresetLocal
                        val hasStoredKey = when {
                            isGeminiProvider -> apiKeyStatus.hasGeminiKey
                            isOpenRouterProvider -> apiKeyStatus.hasOpenRouterKey
                            isOpenAiProvider -> apiKeyStatus.hasOpenAiKey
                            isMiniMaxProvider -> apiKeyStatus.hasMiniMaxKey
                            isOpenAiCompatProvider -> viewModel.hasOpenAiCompatApiKey(selectedCompatPreset)
                            isOpenCodeGoProvider -> apiKeyStatus.hasOpenCodeGoKey
                            isClinePassProvider -> apiKeyStatus.hasClinePassKey
                            isAlibabaCodingPlanProvider -> apiKeyStatus.hasAlibabaCodingPlanKey
                            else -> apiKeyStatus.hasZaiKey
                        }
                        val keyValue = when {
                            isGeminiProvider -> apiKeyInput
                            isOpenRouterProvider -> openRouterApiKeyInput
                            isOpenAiProvider -> openAiApiKeyInput
                            isMiniMaxProvider -> miniMaxApiKeyInput
                            isOpenAiCompatProvider -> openAiCompatApiKeyInput
                            isOpenCodeGoProvider -> openCodeGoApiKeyInput
                            isClinePassProvider -> clinePassApiKeyInput
                            isAlibabaCodingPlanProvider -> alibabaCodingPlanApiKeyInput
                            else -> zaiApiKeyInput
                        }
                        val keyVisible = when {
                            isGeminiProvider -> geminiKeyVisible
                            isOpenRouterProvider -> openRouterKeyVisible
                            isOpenAiProvider -> openAiKeyVisible
                            isMiniMaxProvider -> miniMaxKeyVisible
                            isOpenAiCompatProvider -> openAiCompatKeyVisible
                            isOpenCodeGoProvider -> openCodeGoKeyVisible
                            isClinePassProvider -> clinePassKeyVisible
                            isAlibabaCodingPlanProvider -> alibabaCodingPlanKeyVisible
                            else -> zaiKeyVisible
                        }
                        val keyLabel = when {
                            isGeminiProvider -> "Gemini API Key"
                            isOpenRouterProvider -> "OpenRouter API Key"
                            isOpenAiProvider -> "OpenAI API Key"
                            isMiniMaxProvider -> "MiniMax API Key"
                            isOpenAiCompatProvider -> "OpenAI (Custom) API Key"
                            isOpenCodeGoProvider -> "OpenCode Go API Key"
                            isClinePassProvider -> "Cline Pass API Key"
                            isAlibabaCodingPlanProvider -> "Alibaba Coding Plan API Key"
                            else -> "Z.ai Coding Plan API Key"
                        }
                        val savedKeyPlaceholder = when {
                            isGeminiProvider -> "保存済みのGemini APIキーを使用中（表示するにはアイコンをタップ）"
                            isOpenRouterProvider -> "保存済みのOpenRouter APIキーを使用中（表示するにはアイコンをタップ）"
                            isOpenAiProvider -> "保存済みのOpenAI APIキーを使用中（表示するにはアイコンをタップ）"
                            isMiniMaxProvider -> "保存済みのMiniMax APIキーを使用中（表示するにはアイコンをタップ）"
                            isOpenAiCompatProvider -> "保存済みのOpenAI (Custom) APIキーを使用中（表示するにはアイコンをタップ）"
                            isOpenCodeGoProvider -> "保存済みのOpenCode Go APIキーを使用中（表示するにはアイコンをタップ）"
                            isClinePassProvider -> "保存済みのCline Pass APIキーを使用中（表示するにはアイコンをタップ）"
                            isAlibabaCodingPlanProvider -> "保存済みのAlibaba Coding Plan APIキーを使用中（表示するにはアイコンをタップ）"
                            else -> "保存済みのZ.ai Coding Plan APIキーを使用中（表示するにはアイコンをタップ）"
                        }

                        YamabikoTextField(
                            value = keyValue,
                            onValueChange = {
                                when {
                                    isGeminiProvider -> {
                                        apiKeyInput = it
                                        geminiKeyDirty = true
                                        geminiKeyLoadedFromStorage = false
                                        geminiKeyVisible = true
                                    }
                                    isOpenRouterProvider -> {
                                        openRouterApiKeyInput = it
                                        openRouterKeyDirty = true
                                        openRouterKeyLoadedFromStorage = false
                                        openRouterKeyVisible = true
                                    }
                                    isOpenAiProvider -> {
                                        openAiApiKeyInput = it
                                        openAiKeyDirty = true
                                        openAiKeyLoadedFromStorage = false
                                        openAiKeyVisible = true
                                    }
                                    isMiniMaxProvider -> {
                                        miniMaxApiKeyInput = it
                                        miniMaxKeyDirty = true
                                        miniMaxKeyLoadedFromStorage = false
                                        miniMaxKeyVisible = true
                                    }
                                    isOpenAiCompatProvider -> {
                                        openAiCompatApiKeyInput = it
                                        openAiCompatKeyDirty = true
                                        openAiCompatKeyLoadedFromStorage = false
                                        openAiCompatKeyVisible = true
                                    }
                                    isOpenCodeGoProvider -> {
                                        openCodeGoApiKeyInput = it
                                        openCodeGoKeyDirty = true
                                        openCodeGoKeyLoadedFromStorage = false
                                        openCodeGoKeyVisible = true
                                    }
                                    isClinePassProvider -> {
                                        clinePassApiKeyInput = it
                                        clinePassKeyDirty = true
                                        clinePassKeyLoadedFromStorage = false
                                        clinePassKeyVisible = true
                                    }
                                    isAlibabaCodingPlanProvider -> {
                                        alibabaCodingPlanApiKeyInput = it
                                        alibabaCodingPlanKeyDirty = true
                                        alibabaCodingPlanKeyLoadedFromStorage = false
                                        alibabaCodingPlanKeyVisible = true
                                    }
                                    else -> {
                                        zaiApiKeyInput = it
                                        zaiKeyDirty = true
                                        zaiKeyLoadedFromStorage = false
                                        zaiKeyVisible = true
                                    }
                                }
                            },
                            label = { Text(keyLabel) },
                            placeholder = {
                                Text(
                                    if (hasStoredKey && keyValue.isEmpty()) {
                                        savedKeyPlaceholder
                                    } else {
                                        "APIキーを入力"
                                    }
                                )
                            },
                            singleLine = true,
                            visualTransformation = if (keyVisible) VisualTransformation.None else PasswordVisualTransformation(),
                            trailingIcon = {
                                if (hasStoredKey || keyValue.isNotEmpty()) {
                                    IconButton(
                                        onClick = {
                                            coroutineScope.launch {
                                                when {
                                                    isGeminiProvider -> {
                                                        if (geminiKeyVisible) {
                                                            if (geminiKeyLoadedFromStorage) {
                                                                apiKeyInput = ""
                                                                geminiKeyLoadedFromStorage = false
                                                                geminiKeyDirty = false
                                                            }
                                                            geminiKeyVisible = false
                                                        } else {
                                                            if (hasStoredKey && apiKeyInput.isBlank()) {
                                                                val revealed = viewModel.revealApiKey("GEMINI")
                                                                apiKeyInput = revealed.orEmpty()
                                                                geminiKeyLoadedFromStorage = !revealed.isNullOrEmpty()
                                                                geminiKeyDirty = false
                                                            }
                                                            geminiKeyVisible = true
                                                        }
                                                    }
                                                    isOpenRouterProvider -> {
                                                        if (openRouterKeyVisible) {
                                                            if (openRouterKeyLoadedFromStorage) {
                                                                openRouterApiKeyInput = ""
                                                                openRouterKeyLoadedFromStorage = false
                                                                openRouterKeyDirty = false
                                                            }
                                                            openRouterKeyVisible = false
                                                        } else {
                                                            if (hasStoredKey && openRouterApiKeyInput.isBlank()) {
                                                                val revealed = viewModel.revealApiKey("OPENROUTER")
                                                                openRouterApiKeyInput = revealed.orEmpty()
                                                                openRouterKeyLoadedFromStorage = !revealed.isNullOrEmpty()
                                                                openRouterKeyDirty = false
                                                            }
                                                            openRouterKeyVisible = true
                                                        }
                                                    }
                                                    isOpenAiProvider -> {
                                                        if (openAiKeyVisible) {
                                                            if (openAiKeyLoadedFromStorage) {
                                                                openAiApiKeyInput = ""
                                                                openAiKeyLoadedFromStorage = false
                                                                openAiKeyDirty = false
                                                            }
                                                            openAiKeyVisible = false
                                                        } else {
                                                            if (hasStoredKey && openAiApiKeyInput.isBlank()) {
                                                                val revealed = viewModel.revealApiKey("OPENAI")
                                                                openAiApiKeyInput = revealed.orEmpty()
                                                                openAiKeyLoadedFromStorage = !revealed.isNullOrEmpty()
                                                                openAiKeyDirty = false
                                                            }
                                                            openAiKeyVisible = true
                                                        }
                                                    }
                                                    isMiniMaxProvider -> {
                                                        if (miniMaxKeyVisible) {
                                                            if (miniMaxKeyLoadedFromStorage) {
                                                                miniMaxApiKeyInput = ""
                                                                miniMaxKeyLoadedFromStorage = false
                                                                miniMaxKeyDirty = false
                                                            }
                                                            miniMaxKeyVisible = false
                                                        } else {
                                                            if (hasStoredKey && miniMaxApiKeyInput.isBlank()) {
                                                                val revealed = viewModel.revealApiKey("MINIMAX")
                                                                miniMaxApiKeyInput = revealed.orEmpty()
                                                                miniMaxKeyLoadedFromStorage = !revealed.isNullOrEmpty()
                                                                miniMaxKeyDirty = false
                                                            }
                                                            miniMaxKeyVisible = true
                                                        }
                                                    }
                                                    isOpenAiCompatProvider -> {
                                                        val presetName = selectedCompatPreset
                                                        if (presetName.isNullOrBlank()) return@launch
                                                        if (openAiCompatKeyVisible) {
                                                            if (openAiCompatKeyLoadedFromStorage) {
                                                                openAiCompatApiKeyInput = ""
                                                                openAiCompatKeyLoadedFromStorage = false
                                                                openAiCompatKeyDirty = false
                                                            }
                                                            openAiCompatKeyVisible = false
                                                        } else {
                                                            if (hasStoredKey && openAiCompatApiKeyInput.isBlank()) {
                                                                val revealed = viewModel.revealOpenAiCompatApiKey(presetName)
                                                                openAiCompatApiKeyInput = revealed.orEmpty()
                                                                openAiCompatKeyLoadedFromStorage = !revealed.isNullOrEmpty()
                                                                openAiCompatKeyDirty = false
                                                            }
                                                            openAiCompatKeyVisible = true
                                                        }
                                                    }
                                                    isOpenCodeGoProvider -> {
                                                        if (openCodeGoKeyVisible) {
                                                            if (openCodeGoKeyLoadedFromStorage) {
                                                                openCodeGoApiKeyInput = ""
                                                                openCodeGoKeyLoadedFromStorage = false
                                                                openCodeGoKeyDirty = false
                                                            }
                                                            openCodeGoKeyVisible = false
                                                        } else {
                                                            if (hasStoredKey && openCodeGoApiKeyInput.isBlank()) {
                                                                val revealed = viewModel.revealApiKey("OPENCODE_GO")
                                                                openCodeGoApiKeyInput = revealed.orEmpty()
                                                                openCodeGoKeyLoadedFromStorage = !revealed.isNullOrEmpty()
                                                                openCodeGoKeyDirty = false
                                                            }
                                                            openCodeGoKeyVisible = true
                                                        }
                                                    }
                                                    isClinePassProvider -> {
                                                        if (clinePassKeyVisible) {
                                                            if (clinePassKeyLoadedFromStorage) {
                                                                clinePassApiKeyInput = ""
                                                                clinePassKeyLoadedFromStorage = false
                                                                clinePassKeyDirty = false
                                                            }
                                                            clinePassKeyVisible = false
                                                        } else {
                                                            if (hasStoredKey && clinePassApiKeyInput.isBlank()) {
                                                                val revealed = viewModel.revealApiKey("CLINEPASS")
                                                                clinePassApiKeyInput = revealed.orEmpty()
                                                                clinePassKeyLoadedFromStorage = !revealed.isNullOrEmpty()
                                                                clinePassKeyDirty = false
                                                            }
                                                            clinePassKeyVisible = true
                                                        }
                                                    }
                                                    isAlibabaCodingPlanProvider -> {
                                                        if (alibabaCodingPlanKeyVisible) {
                                                            if (alibabaCodingPlanKeyLoadedFromStorage) {
                                                                alibabaCodingPlanApiKeyInput = ""
                                                                alibabaCodingPlanKeyLoadedFromStorage = false
                                                                alibabaCodingPlanKeyDirty = false
                                                            }
                                                            alibabaCodingPlanKeyVisible = false
                                                        } else {
                                                            if (hasStoredKey && alibabaCodingPlanApiKeyInput.isBlank()) {
                                                                val revealed = viewModel.revealApiKey("ALIBABA_CODING_PLAN")
                                                                alibabaCodingPlanApiKeyInput = revealed.orEmpty()
                                                                alibabaCodingPlanKeyLoadedFromStorage = !revealed.isNullOrEmpty()
                                                                alibabaCodingPlanKeyDirty = false
                                                            }
                                                            alibabaCodingPlanKeyVisible = true
                                                        }
                                                    }
                                                    else -> {
                                                        if (zaiKeyVisible) {
                                                            if (zaiKeyLoadedFromStorage) {
                                                                zaiApiKeyInput = ""
                                                                zaiKeyLoadedFromStorage = false
                                                                zaiKeyDirty = false
                                                            }
                                                            zaiKeyVisible = false
                                                        } else {
                                                            if (hasStoredKey && zaiApiKeyInput.isBlank()) {
                                                                val revealed = viewModel.revealApiKey("ZAI")
                                                                zaiApiKeyInput = revealed.orEmpty()
                                                                zaiKeyLoadedFromStorage = !revealed.isNullOrEmpty()
                                                                zaiKeyDirty = false
                                                            }
                                                            zaiKeyVisible = true
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    ) {
                                        Icon(
                                            imageVector = if (keyVisible) Icons.Default.VisibilityOff else Icons.Default.Visibility,
                                            contentDescription = null
                                        )
                                    }
                                }
                            },
                            modifier = Modifier.fillMaxWidth()
                        )

                        if (hasStoredKey) {
                            TextButton(
                                onClick = {
                                    when {
                                        isGeminiProvider -> viewModel.clearApiKey("GEMINI")
                                        isOpenRouterProvider -> viewModel.clearApiKey("OPENROUTER")
                                        isOpenAiProvider -> viewModel.clearApiKey("OPENAI")
                                        isMiniMaxProvider -> viewModel.clearApiKey("MINIMAX")
                                        isOpenAiCompatProvider -> {
                                            val presetName = selectedCompatPreset
                                            if (presetName != null) viewModel.clearOpenAiCompatApiKey(presetName)
                                        }
                                        isOpenCodeGoProvider -> viewModel.clearApiKey("OPENCODE_GO")
                                        isClinePassProvider -> viewModel.clearApiKey("CLINEPASS")
                                        isAlibabaCodingPlanProvider -> viewModel.clearApiKey("ALIBABA_CODING_PLAN")
                                        else -> viewModel.clearApiKey("ZAI")
                                    }
                                },
                                modifier = Modifier.align(Alignment.End)
                            ) {
                                Text("保存済みキーを削除")
                            }
                        }
                    }
                }
            }
        }
        if (apiProvider == "OPENAI") {
            item {
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
                    border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.6f)),
                    elevation = CardDefaults.cardElevation(defaultElevation = 1.dp)
                ) {
                    Column(
                        modifier = Modifier.padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(16.dp)
                    ) {
                        Text(
                            text = "Endpoint",
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.SemiBold
                        )
                        YamabikoTextField(
                            value = openAiBaseUrl,
                            onValueChange = { openAiBaseUrl = it },
                            label = { Text("OpenAI Base URL") },
                            modifier = Modifier.fillMaxWidth()
                        )
                    }
                }
            }
        }
        if (apiProvider == "MINIMAX") {
            item {
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
                    border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.6f)),
                    elevation = CardDefaults.cardElevation(defaultElevation = 1.dp)
                ) {
                    Column(
                        modifier = Modifier.padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(16.dp)
                    ) {
                        Text(
                            text = "MiniMax Endpoint",
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.SemiBold
                        )
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            TextButton(onClick = { miniMaxBaseUrl = MiniMaxUtils.INTERNATIONAL_BASE_URL }) {
                                Text("Global")
                            }
                            TextButton(onClick = { miniMaxBaseUrl = MiniMaxUtils.CHINA_BASE_URL }) {
                                Text("China")
                            }
                        }
                        YamabikoTextField(
                            value = miniMaxBaseUrl,
                            onValueChange = { miniMaxBaseUrl = it },
                            label = { Text("MiniMax Base URL") },
                            modifier = Modifier.fillMaxWidth()
                        )
                    }
                }
            }
        }
        if (apiProvider == "OPENAI_COMPAT") {
            item {
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
                    border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.6f)),
                    elevation = CardDefaults.cardElevation(defaultElevation = 1.dp)
                ) {
                    Column(
                        modifier = Modifier.padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(16.dp)
                    ) {
                        Text(
                            text = "OpenAI (Custom) Presets",
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.SemiBold
                        )
                        val selected = selectedOpenAiCompatPresetLocal
                        val hasPresets = openAiCompatPresetsLocal.isNotEmpty()
                        YamabikoSelectRow(
                            title = "Selected Preset",
                            value = selected ?: "未選択",
                            enabled = hasPresets,
                            onClick = { activeSheet = SettingsSheet.OpenAiCompatPreset }
                        )
                        if (openAiCompatPresetsLocal.isEmpty()) {
                            Text(
                                "No presets yet. Add one below.",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                        Row(modifier = Modifier.fillMaxWidth()) {
                            YamabikoTextField(
                                value = compatPresetName,
                                onValueChange = { compatPresetName = it },
                                label = { Text("Preset Name") },
                                modifier = Modifier.weight(1f)
                            )
                            Spacer(modifier = Modifier.width(8.dp))
                            YamabikoTextField(
                                value = compatPresetBaseUrl,
                                onValueChange = { compatPresetBaseUrl = it },
                                label = { Text("Base URL") },
                                modifier = Modifier.weight(1.2f)
                            )
                        }
                        Row {
                            TextButton(onClick = {
                                if (compatPresetName.isNotBlank() && compatPresetBaseUrl.isNotBlank()) {
                                    val normalizedName = compatPresetName.trim()
                                    val normalizedBaseUrl = compatPresetBaseUrl.trim()
                                    val idx = openAiCompatPresetsLocal.indexOfFirst { it.name.equals(normalizedName, ignoreCase = true) }
                                    if (idx >= 0) {
                                        openAiCompatPresetsLocal[idx] = OpenAiCompatPreset(normalizedName, normalizedBaseUrl)
                                    } else {
                                        openAiCompatPresetsLocal.add(OpenAiCompatPreset(normalizedName, normalizedBaseUrl))
                                    }
                                    selectedOpenAiCompatPresetLocal = normalizedName
                                    viewModel.addOrUpdateOpenAiCompatPreset(normalizedName, normalizedBaseUrl)
                                }
                            }) { Text("Add/Update Preset") }
                            if (!selected.isNullOrBlank()) {
                                TextButton(
                                    onClick = {
                                        openAiCompatPresetsLocal.removeAll { it.name.equals(selected, ignoreCase = true) }
                                        if (selectedOpenAiCompatPresetLocal?.equals(selected, ignoreCase = true) == true) {
                                            selectedOpenAiCompatPresetLocal = null
                                        }
                                        viewModel.removeOpenAiCompatPreset(selected)
                                        openAiCompatApiKeyInput = ""
                                        openAiCompatKeyDirty = false
                                        openAiCompatKeyVisible = false
                                        openAiCompatKeyLoadedFromStorage = false
                                    },
                                    colors = ButtonDefaults.textButtonColors(
                                        contentColor = MaterialTheme.colorScheme.error
                                    )
                                ) { Text("Remove Selected") }
                            }
                        }
                    }
                }
            }
        }
        if (apiProvider == "OPENCODE_GO") {
            item {
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
                    border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.6f)),
                    elevation = CardDefaults.cardElevation(defaultElevation = 1.dp)
                ) {
                    Column(
                        modifier = Modifier.padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(16.dp)
                    ) {
                        Text(
                            text = "OpenCode Go",
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.SemiBold
                        )
                        LabeledValueBlock(
                            label = "Endpoint",
                            value = ProviderCatalog.defaultOpenCodeGoBaseUrl
                        )
                        Text(
                            text = "MiniMax M2.7/M2.5 と Qwen3.5/3.6 Plus、Qwen3.7 Max は /messages、それ以外の公式 Go モデルは /chat/completions に送信します。未掲載モデルは endpoint を安全に判定できないため、実行時に明示エラーで停止します。",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            }
        }
        if (apiProvider == "CLINEPASS") {
            item {
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
                    border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.6f)),
                    elevation = CardDefaults.cardElevation(defaultElevation = 1.dp)
                ) {
                    Column(
                        modifier = Modifier.padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(16.dp)
                    ) {
                        Text(
                            text = "Cline Pass",
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.SemiBold
                        )
                        LabeledValueBlock(
                            label = "Endpoint",
                            value = ProviderCatalog.defaultClinePassBaseUrl
                        )
                        Text(
                            text = "Cline dashboard の Settings > API Keys で発行したキーを使用します。すべてのモデルは /chat/completions に送信します。",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            }
        }
        if (apiProvider == "ALIBABA_CODING_PLAN") {
            item {
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
                    border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.6f)),
                    elevation = CardDefaults.cardElevation(defaultElevation = 1.dp)
                ) {
                    Column(
                        modifier = Modifier.padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(16.dp)
                    ) {
                        Text(
                            text = "Alibaba Coding Plan",
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.SemiBold
                        )
                        LabeledValueBlock(
                            label = "Base URL",
                            value = ProviderCatalog.defaultAlibabaCodingPlanBaseUrl
                        )
                        Text(
                            text = "Coding Plan 専用キーは sk-sp- で始まります。Android版は Anthropic 互換の /v1/messages を固定 URL で使います。MCP は remote HTTPS server のみ対応し、stdio MCP はアプリ内では利用できません。",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        SettingsToggleRow(
                            title = "Remote MCP",
                            description = "Alibaba Coding Plan に remote MCP server を渡します",
                            checked = alibabaMcpEnabled,
                            onCheckedChange = { alibabaMcpEnabled = it },
                            leadingContent = { Icon(Icons.Default.Extension, contentDescription = null) }
                        )
                        if (alibabaMcpEnabled) {
                            YamabikoTextField(
                                value = alibabaMcpServerUrl,
                                onValueChange = { alibabaMcpServerUrl = it },
                                label = { Text("MCP Server URL") },
                                placeholder = { Text("https://...") },
                                modifier = Modifier.fillMaxWidth(),
                                singleLine = true
                            )
                            YamabikoTextField(
                                value = alibabaMcpServerName,
                                onValueChange = { alibabaMcpServerName = it },
                                label = { Text("MCP Server Name") },
                                placeholder = { Text(ProviderCatalog.alibabaMcpDefaultServerName) },
                                modifier = Modifier.fillMaxWidth(),
                                singleLine = true
                            )
                            YamabikoTextField(
                                value = alibabaMcpAuthorizationTokenInput,
                                onValueChange = {
                                    alibabaMcpAuthorizationTokenInput = it
                                    alibabaMcpTokenDirty = true
                                    alibabaMcpTokenLoadedFromStorage = false
                                    alibabaMcpTokenVisible = true
                                },
                                label = { Text("Authorization Token (optional)") },
                                placeholder = {
                                    if (apiKeyStatus.hasAlibabaMcpAuthorizationToken &&
                                        alibabaMcpAuthorizationTokenInput.isEmpty()
                                    ) {
                                        Text("保存済みトークンを使用中（表示するにはアイコンをタップ）")
                                    } else {
                                        Text("Bearer token if required")
                                    }
                                },
                                singleLine = true,
                                visualTransformation = if (alibabaMcpTokenVisible) {
                                    VisualTransformation.None
                                } else {
                                    PasswordVisualTransformation()
                                },
                                trailingIcon = {
                                    if (apiKeyStatus.hasAlibabaMcpAuthorizationToken ||
                                        alibabaMcpAuthorizationTokenInput.isNotEmpty()
                                    ) {
                                        IconButton(onClick = {
                                            coroutineScope.launch {
                                                if (alibabaMcpTokenVisible) {
                                                    if (alibabaMcpTokenLoadedFromStorage) {
                                                        alibabaMcpAuthorizationTokenInput = ""
                                                        alibabaMcpTokenLoadedFromStorage = false
                                                        alibabaMcpTokenDirty = false
                                                    }
                                                    alibabaMcpTokenVisible = false
                                                } else {
                                                    if (apiKeyStatus.hasAlibabaMcpAuthorizationToken &&
                                                        alibabaMcpAuthorizationTokenInput.isBlank()
                                                    ) {
                                                        val revealed = viewModel.revealAlibabaMcpAuthorizationToken()
                                                        alibabaMcpAuthorizationTokenInput = revealed.orEmpty()
                                                        alibabaMcpTokenLoadedFromStorage = !revealed.isNullOrEmpty()
                                                        alibabaMcpTokenDirty = false
                                                    }
                                                    alibabaMcpTokenVisible = true
                                                }
                                            }
                                        }) {
                                            Icon(
                                                imageVector = if (alibabaMcpTokenVisible) {
                                                    Icons.Default.VisibilityOff
                                                } else {
                                                    Icons.Default.Visibility
                                                },
                                                contentDescription = null
                                            )
                                        }
                                    }
                                },
                                modifier = Modifier.fillMaxWidth()
                            )
                            YamabikoTextField(
                                value = alibabaMcpAllowedTools,
                                onValueChange = { alibabaMcpAllowedTools = it },
                                label = { Text("Allowed tools (optional)") },
                                placeholder = { Text("search, scrape") },
                                modifier = Modifier.fillMaxWidth(),
                                minLines = 2,
                                maxLines = 4
                            )
                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                TextButton(onClick = {
                                    alibabaMcpServerName = ProviderCatalog.alibabaMcpDefaultServerName
                                    if (alibabaMcpServerUrl.isBlank()) {
                                        alibabaMcpServerUrl = ProviderCatalog.firecrawlRemoteMcpUrlTemplate
                                    }
                                }) {
                                    Text("Firecrawl テンプレート")
                                }
                                TextButton(onClick = {
                                    alibabaMcpAuthorizationTokenInput = ""
                                    alibabaMcpTokenDirty = true
                                    alibabaMcpTokenLoadedFromStorage = false
                                    alibabaMcpTokenVisible = false
                                }) {
                                    Text("保存済みトークンを削除")
                                }
                            }
                            Text(
                                text = "ツール名を空欄にするとサーバーが公開する全ツールを許可し、指定するとそのツールだけ有効化します。",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                }
            }
        }
        item {
            Card(
                modifier = Modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
                border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.6f)),
                elevation = CardDefaults.cardElevation(defaultElevation = 1.dp)
            ) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(16.dp)
                ) {
                    Text(
                        text = "Model",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold
                    )
                    when (apiProvider) {
                        "OPENROUTER" -> {
                            OpenRouterModelSelector(
                                selectedModel = model,
                                onModelSelected = { model = it },
                                models = openRouterModels,
                                isLoading = openRouterModelsLoading,
                                error = openRouterModelsError,
                                onRefresh = { viewModel.refreshOpenRouterModels() },
                                selectedProvider = selectedProvider,
                                onProviderSelected = { selectedProvider = it },
                                pinnedModelIds = openRouterPinnedModels,
                                recentModelIds = openRouterRecentModels,
                                onTogglePinned = { toggleOpenRouterPinnedModel(it) },
                                onRecentUsed = { registerOpenRouterRecentModel(it) }
                            )
                        }
                        "CODEX_AUTH" -> {
                            val preset = CodexModelPresets.findPreset(model)
                            val label = preset?.displayName ?: model
                            YamabikoSelectRow(
                                title = "Model",
                                value = label,
                                onClick = { activeSheet = SettingsSheet.CodexModel }
                            )
                            preset?.description?.let {
                                Text(
                                    text = it,
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                            YamabikoTextField(
                                value = model,
                                onValueChange = { model = it },
                                label = { Text("Custom Model ID") },
                                placeholder = { Text(CodexModelPresets.defaultModel()) },
                                supportingText = { Text("Type a model id to use a custom Codex model.") },
                                modifier = Modifier.fillMaxWidth(),
                                singleLine = true
                            )
                        }
                        "SUPERGROK" -> {
                            val selectedModel = com.porarri.yamabikochat.data.remote.SuperGrokModelCatalog.modelFor(model)
                            YamabikoSelectRow(
                                title = "SuperGrok Model",
                                value = selectedModel?.displayName ?: model.ifBlank {
                                    com.porarri.yamabikochat.data.remote.SuperGrokModelCatalog.defaultModel
                                },
                                onClick = { activeSheet = SettingsSheet.SuperGrokModel }
                            )
                            selectedModel?.description?.let {
                                Text(
                                    text = it,
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                            YamabikoTextField(
                                value = model,
                                onValueChange = { model = it },
                                label = { Text("Custom Model ID") },
                                placeholder = { Text(com.porarri.yamabikochat.data.remote.SuperGrokModelCatalog.defaultModel) },
                                supportingText = { Text("Type a model id to use a custom SuperGrok model.") },
                                modifier = Modifier.fillMaxWidth(),
                                singleLine = true
                            )
                        }
                        "ALIBABA_CODING_PLAN" -> {
                            val selectedModel = model.ifBlank { AlibabaCodingPlanModelCatalog.defaultModel }
                            var showAlibabaModelSheet by remember { mutableStateOf(false) }
                            YamabikoSelectRow(
                                title = "Alibaba Model",
                                value = selectedModel,
                                onClick = { showAlibabaModelSheet = true }
                            )
                            if (showAlibabaModelSheet) {
                                YamabikoOptionBottomSheet(
                                    title = "Alibaba Model",
                                    options = AlibabaCodingPlanModelCatalog.supportedModels.map {
                                        YamabikoOption(key = it, title = it)
                                    },
                                    selectedKey = selectedModel,
                                    onOptionSelected = { option -> model = option.key },
                                    onDismissRequest = { showAlibabaModelSheet = false }
                                )
                            }
                            YamabikoTextField(
                                value = model,
                                onValueChange = { model = it },
                                label = { Text("Model") },
                                placeholder = { Text(AlibabaCodingPlanModelCatalog.defaultModel) },
                                modifier = Modifier.fillMaxWidth(),
                                singleLine = true
                            )
                        }
                        "OPENCODE_GO" -> {
                            val selectedModel = OpenCodeGoModelCatalog.modelFor(model)
                            var showOpenCodeGoModelSheet by remember { mutableStateOf(false) }
                            YamabikoSelectRow(
                                title = "OpenCode Go Model",
                                value = selectedModel?.displayName ?: model.ifBlank { OpenCodeGoModelCatalog.defaultModel },
                                onClick = { showOpenCodeGoModelSheet = true }
                            )
                            if (showOpenCodeGoModelSheet) {
                                YamabikoOptionBottomSheet(
                                    title = "OpenCode Go Model",
                                    options = OpenCodeGoModelCatalog.supportedModels.map { option ->
                                        val endpoint = when (option.endpointKind) {
                                            OpenCodeGoEndpointKind.CHAT_COMPLETIONS -> "chat/completions"
                                            OpenCodeGoEndpointKind.MESSAGES -> "messages"
                                        }
                                        YamabikoOption(
                                            key = option.id,
                                            title = option.displayName,
                                            subtitle = endpoint
                                        )
                                    },
                                    selectedKey = selectedModel?.id ?: model,
                                    onOptionSelected = { option -> model = option.key },
                                    onDismissRequest = { showOpenCodeGoModelSheet = false }
                                )
                            }
                            selectedModel?.let { selected ->
                                val endpoint = when (selected.endpointKind) {
                                    OpenCodeGoEndpointKind.CHAT_COMPLETIONS -> "/chat/completions"
                                    OpenCodeGoEndpointKind.MESSAGES -> "/messages"
                                }
                                Text(
                                    text = "Endpoint: $endpoint",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                            YamabikoTextField(
                                value = model,
                                onValueChange = { model = it },
                                label = { Text("Model") },
                                placeholder = { Text(OpenCodeGoModelCatalog.defaultModel) },
                                supportingText = {
                                    Text("未掲載モデルは endpoint を安全に判定できないため、実行時に明示エラーで停止します。")
                                },
                                modifier = Modifier.fillMaxWidth(),
                                singleLine = true
                            )
                        }
                        "CLINEPASS" -> {
                            val selectedModel = ClinePassModelCatalog.modelFor(model)
                            var showClinePassModelSheet by remember { mutableStateOf(false) }
                            YamabikoSelectRow(
                                title = "Cline Pass Model",
                                value = selectedModel?.displayName ?: model.ifBlank { ClinePassModelCatalog.defaultModel },
                                onClick = { showClinePassModelSheet = true }
                            )
                            if (showClinePassModelSheet) {
                                YamabikoOptionBottomSheet(
                                    title = "Cline Pass Model",
                                    options = ClinePassModelCatalog.supportedModels.map { option ->
                                        YamabikoOption(
                                            key = option.id,
                                            title = option.displayName,
                                            subtitle = "chat/completions"
                                        )
                                    },
                                    selectedKey = selectedModel?.id ?: model,
                                    onOptionSelected = { option -> model = option.key },
                                    onDismissRequest = { showClinePassModelSheet = false }
                                )
                            }
                            YamabikoTextField(
                                value = model,
                                onValueChange = { model = it },
                                label = { Text("Model") },
                                placeholder = { Text(ClinePassModelCatalog.defaultModel) },
                                modifier = Modifier.fillMaxWidth(),
                                singleLine = true
                            )
                        }
                        "ZAI" -> {
                            val selectedModel = model.ifBlank { ZaiCodingPlanModelCatalog.defaultModel }
                            var showZaiModelSheet by remember { mutableStateOf(false) }
                            YamabikoSelectRow(
                                title = "Z.ai Coding Plan Model",
                                value = selectedModel,
                                onClick = { showZaiModelSheet = true }
                            )
                            if (showZaiModelSheet) {
                                YamabikoOptionBottomSheet(
                                    title = "Z.ai Coding Plan Model",
                                    options = ZaiCodingPlanModelCatalog.supportedModels.map {
                                        YamabikoOption(key = it, title = it, subtitle = "chat/completions")
                                    },
                                    selectedKey = selectedModel,
                                    onOptionSelected = { option -> model = option.key },
                                    onDismissRequest = { showZaiModelSheet = false }
                                )
                            }
                            Text(
                                text = "Coding Plan 専用 endpoint で利用可能なモデルだけを表示しています。",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                        else -> if (ModelsDevMergedProvider.catalogIdFor(apiProvider) != null &&
                            !apiProvider.equals("OPENROUTER", ignoreCase = true)
                        ) {
                            val catalogId = ModelsDevMergedProvider.catalogIdFor(apiProvider)
                            val catalogProvider = modelsDevCatalogState.providers.firstOrNull {
                                it.id == catalogId
                            }
                            var showModelsDevModelSheet by remember { mutableStateOf(false) }
                            val selectedCatalogModel = catalogProvider?.models?.firstOrNull { it.id == model }
                            YamabikoSelectRow(
                                title = "Model",
                                value = selectedCatalogModel?.name ?: model.ifBlank { "モデルを選択" },
                                onClick = { showModelsDevModelSheet = true }
                            )
                            if (showModelsDevModelSheet) {
                                YamabikoOptionBottomSheet(
                                    title = catalogProvider?.name ?: "Model",
                                    options = catalogProvider?.models.orEmpty().map { option ->
                                        val details = buildList {
                                            option.limits.context?.let { add("context $it") }
                                            if (option.reasoning) add("reasoning")
                                            if (option.toolCall) add("tools")
                                            option.description?.let { add(it) }
                                        }.joinToString(" ・ ")
                                        YamabikoOption(option.id, option.name, details.takeIf { it.isNotBlank() })
                                    },
                                    selectedKey = model,
                                    onOptionSelected = { option -> model = option.key },
                                    onDismissRequest = { showModelsDevModelSheet = false },
                                    searchable = true,
                                    searchPlaceholder = "モデルを検索"
                                )
                            }
                            selectedCatalogModel?.description?.let {
                                Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                            val savedReasoningEffort = selectedCatalogModel
                                ?.takeIf { ProviderReference(apiProvider).isModelsDev }
                                ?.let { selected ->
                                    viewModel.modelsDevReasoningEffort(requireNotNull(catalogProvider).id, selected.id)
                                }
                                .orEmpty()
                            if (ProviderReference(apiProvider).isModelsDev &&
                                selectedCatalogModel != null &&
                                selectedCatalogModel.shouldShowReasoningEffortPreference(savedReasoningEffort)
                            ) {
                                var showReasoningEffortSheet by remember { mutableStateOf(false) }
                                var selectedReasoningEffort by remember(apiProvider, model) {
                                    mutableStateOf(savedReasoningEffort)
                                }
                                YamabikoSelectRow(
                                    title = "Reasoning effort",
                                    value = when {
                                        selectedReasoningEffort.isBlank() -> "プロバイダー既定"
                                        selectedReasoningEffort in selectedCatalogModel.supportedReasoningEfforts -> selectedReasoningEffort
                                        else -> "$selectedReasoningEffort（現在は非対応）"
                                    },
                                    onClick = { showReasoningEffortSheet = true }
                                )
                                if (showReasoningEffortSheet) {
                                    YamabikoOptionBottomSheet(
                                        title = "Reasoning effort",
                                        options = buildList {
                                            add(YamabikoOption("", "プロバイダー既定"))
                                            if (selectedReasoningEffort.isNotEmpty() &&
                                                selectedReasoningEffort !in selectedCatalogModel.supportedReasoningEfforts
                                            ) {
                                                add(YamabikoOption(
                                                    selectedReasoningEffort,
                                                    "$selectedReasoningEffort（現在は非対応）"
                                                ))
                                            }
                                            addAll(selectedCatalogModel.supportedReasoningEfforts.map { effort ->
                                                YamabikoOption(effort, effort)
                                            })
                                        },
                                        selectedKey = selectedReasoningEffort,
                                        onOptionSelected = { option ->
                                            selectedReasoningEffort = option.key
                                            viewModel.saveModelsDevReasoningEffort(
                                                catalogProvider.id,
                                                selectedCatalogModel.id,
                                                option.key
                                            )
                                        },
                                        onDismissRequest = { showReasoningEffortSheet = false }
                                    )
                                }
                                Text(
                                    "models.devがこのモデルについて公開している対応値だけを表示します。",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                            when (modelsDevCatalogState.availability) {
                                CatalogAvailability.LOADING -> LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
                                CatalogAvailability.STALE -> Text(
                                    "保存済みのモデル一覧を表示しています。${modelsDevCatalogState.error.orEmpty()}",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.tertiary
                                )
                                CatalogAvailability.ERROR -> Text(
                                    modelsDevCatalogState.error ?: "モデル一覧を取得できませんでした",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.error
                                )
                                else -> Unit
                            }
                            TextButton(onClick = { viewModel.refreshModelsDevCatalog() }) { Text("モデル一覧を更新") }
                            if (model.isNotBlank() && selectedCatalogModel == null) {
                                Text("このモデルは現在のカタログでは利用できません。自動変更は行いません。", color = MaterialTheme.colorScheme.error)
                            }
                        } else {
                            YamabikoTextField(
                                value = model,
                                onValueChange = { model = it },
                                label = { Text("Model") },
                                modifier = Modifier.fillMaxWidth()
                            )
                        }
                    }
                }
            }
        }
        if (apiProvider.startsWith("MODELS_DEV:", ignoreCase = true)) {
            item {
                val provider = modelsDevCatalogState.providers.firstOrNull {
                    it.id == ProviderReference(apiProvider).modelsDevId
                }
                val credentialDrafts = remember(provider?.id) { mutableStateMapOf<String, String>() }
                val requiresManualUrl = provider?.let {
                    ModelsDevProviderAdapterRegistry.profile(it).requiresManualBaseUrl
                } ?: false
                LaunchedEffect(provider?.id) {
                    credentialDrafts.clear()
                    provider?.env.orEmpty().forEach { field ->
                        credentialDrafts[field] = viewModel.modelsDevField(provider!!.id, field)
                    }
                    if (requiresManualUrl) {
                        credentialDrafts["YAMABIKO_BASE_URL"] = viewModel.modelsDevField(provider!!.id, "YAMABIKO_BASE_URL")
                    }
                }
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
                    border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.6f))
                ) {
                    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        Text("${provider?.name ?: "models.dev"} 接続設定", style = MaterialTheme.typography.titleMedium)
                        provider?.env.orEmpty().forEach { field ->
                            val secret = listOf("KEY", "TOKEN", "SECRET", "PASSWORD", "CREDENTIAL").any { field.contains(it) }
                            YamabikoTextField(
                                value = credentialDrafts[field].orEmpty(),
                                onValueChange = { credentialDrafts[field] = it },
                                label = { Text(field) },
                                visualTransformation = if (secret) PasswordVisualTransformation() else VisualTransformation.None,
                                modifier = Modifier.fillMaxWidth(),
                                singleLine = field != "GOOGLE_APPLICATION_CREDENTIALS"
                            )
                        }
                        if (requiresManualUrl) {
                            YamabikoTextField(
                                value = credentialDrafts["YAMABIKO_BASE_URL"].orEmpty(),
                                onValueChange = { credentialDrafts["YAMABIKO_BASE_URL"] = it },
                                label = { Text("完成済み Base URL") },
                                supportingText = { Text("テンプレート変数を展開したURLを入力してください。localhost/LAN接続は安全性を確認してください。") },
                                modifier = Modifier.fillMaxWidth(),
                                singleLine = true
                            )
                        } else {
                            Text(provider?.api.orEmpty(), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        Button(
                            onClick = { provider?.let { viewModel.saveModelsDevFields(it.id, credentialDrafts.toMap()) } },
                            enabled = provider != null
                        ) { Text("接続設定を暗号化して保存") }
                    }
                }
            }
        }
        if (apiProvider == "OPENROUTER") {
            openRouterAdvancedSettingsSection(
                expanded = advancedSettingsExpanded,
                onExpandedChange = { advancedSettingsExpanded = it },
                providerSort = providerSort,
                onProviderSortChange = { providerSort = it },
                providerSelectionMax = providerSelectionMax,
                onProviderSelectionMaxChange = { providerSelectionMax = it },
                preferredProviders = preferredProviders,
                onPreferredProvidersChange = { preferredProviders = it },
                selectedQuantizations = selectedQuantizations,
                onSelectedQuantizationsChange = { selectedQuantizations = it },
                maxPrice = maxPrice,
                onMaxPriceChange = { maxPrice = it },
                allowFallbacks = allowFallbacks,
                onAllowFallbacksChange = { allowFallbacks = it },
                requireParameters = requireParameters,
                onRequireParametersChange = { requireParameters = it },
                modelEndpoints = modelEndpoints,
                providerDirectory = providerDirectory,
                freeModelOnly = isCurrentModelFree
            )
        }
                    }
                    if (selectedTab == 1) {
        item {
            Card(
                modifier = Modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
                border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.6f)),
                elevation = CardDefaults.cardElevation(defaultElevation = 1.dp)
            ) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(16.dp)
                ) {
                    Text(
                        text = "System Prompt Preset",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold
                    )
                    val selectedPreset = selectedSystemPromptPresetLocal
                    YamabikoSelectRow(
                        title = "選択中のプリセット",
                        value = selectedPreset.orEmpty(),
                        onClick = { activeSheet = SettingsSheet.SystemPromptPreset }
                    )
                    if (systemPromptPresetsLocal.isEmpty()) {
                        Text(
                            "プリセットは未登録です。名前を入力して保存してください。",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                    YamabikoTextField(
                        value = systemPromptPresetName,
                        onValueChange = { systemPromptPresetName = it },
                        label = { Text("Preset Name") },
                        modifier = Modifier.fillMaxWidth()
                    )
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        FilledTonalButton(onClick = {
                            val normalizedName = systemPromptPresetName.trim()      
                            if (normalizedName.isBlank()) {
                                Toast.makeText(context, "プリセット名を入力してください。", Toast.LENGTH_SHORT).show()
                                return@FilledTonalButton
                            }
                            val currentPrompt = systemPrompt
                            if (currentPrompt.isBlank()) {
                                Toast.makeText(context, "システムプロンプトを入力してください。", Toast.LENGTH_SHORT).show()
                                return@FilledTonalButton
                            }
                            val idx = systemPromptPresetsLocal.indexOfFirst {
                                it.name.equals(normalizedName, ignoreCase = true)
                            }
                            val updated = SystemPromptPreset(normalizedName, currentPrompt)
                            if (idx >= 0) {
                                systemPromptPresetsLocal[idx] = updated
                            } else {
                                systemPromptPresetsLocal.add(updated)
                            }
                            selectedSystemPromptPresetLocal = normalizedName
                            systemPromptPresetName = normalizedName
                        }) { Text("Save/Update Preset") }
                        if (!selectedPreset.isNullOrBlank()) {
                            TextButton(onClick = {
                                systemPromptPresetsLocal.removeAll { it.name.equals(selectedPreset, ignoreCase = true) }
                                if (selectedSystemPromptPresetLocal?.equals(selectedPreset, ignoreCase = true) == true) {
                                    selectedSystemPromptPresetLocal = null
                                }
                                systemPromptPresetName = ""
                            }) { Text("Remove Selected") }
                        }
                    }
                }
            }
        }
        item {
            Card(
                modifier = Modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
                border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.6f)),
                elevation = CardDefaults.cardElevation(defaultElevation = 1.dp)
            ) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(16.dp)
                ) {
                    Text(
                        text = "System Prompt",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold
                    )
                    YamabikoTextField(
                        value = systemPrompt,
                        onValueChange = { value ->
                            systemPrompt = value
                        },
                        label = { Text("System Prompt") },
                        minLines = 6,
                        maxLines = 12,
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(120.dp)
                    )
                }
            }
        }
                    }
                    if (selectedTab == 0) {
        if (apiProvider == "GEMINI") {
            item {
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
                    border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.6f)),
                    elevation = CardDefaults.cardElevation(defaultElevation = 1.dp)
                ) {
                    Column(
                        modifier = Modifier.padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(16.dp)
                    ) {
                        Text(
                            text = "Gemini Tools",
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.SemiBold
                        )
                        SettingsToggleRow(
                            title = "Google Search",
                            description = "最新情報の検索に利用します",
                            checked = googleSearchEnabled,
                            onCheckedChange = { googleSearchEnabled = it },
                            leadingContent = { Icon(Icons.Default.Search, contentDescription = null) }
                        )
                        SettingsToggleRow(
                            title = "URL Context",
                            description = "URLを参照してコンテキストを取得します",
                            checked = urlContextEnabled,
                            onCheckedChange = { urlContextEnabled = it },
                            leadingContent = { Icon(Icons.Default.Link, contentDescription = null) }
                        )
                        SettingsToggleRow(
                            title = "Code Execution",
                            description = "コード実行ツールを利用します",
                            checked = codeExecutionEnabled,
                            onCheckedChange = { codeExecutionEnabled = it },
                            leadingContent = { Icon(Icons.Default.Code, contentDescription = null) }
                        )
                        SettingsToggleRow(
                            title = "Google Maps",
                            description = "場所情報の取得に利用します",
                            checked = googleMapsEnabled,
                            onCheckedChange = { googleMapsEnabled = it },
                            leadingContent = { Icon(Icons.Default.Map, contentDescription = null) }
                        )
                        SettingsToggleRow(
                            title = "Computer Use",
                            description = "ブラウザ/操作系ツールを利用します",
                            checked = computerUseEnabled,
                            onCheckedChange = { computerUseEnabled = it },
                            leadingContent = { Icon(Icons.Default.DesktopWindows, contentDescription = null) }
                        )
                    }
                }
            }
            item {
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
                    border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.6f)),
                    elevation = CardDefaults.cardElevation(defaultElevation = 1.dp)
                ) {
                    Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(
                                text = "Gemini Advanced (JSON)",
                                style = MaterialTheme.typography.titleMedium,
                                fontWeight = FontWeight.SemiBold,
                                modifier = Modifier.weight(1f)
                            )
                            IconButton(onClick = { geminiAdvancedExpanded = !geminiAdvancedExpanded }) {
                                Icon(
                                    imageVector = if (geminiAdvancedExpanded) Icons.Default.ExpandLess else Icons.Default.ExpandMore,
                                    contentDescription = null
                                )
                            }
                        }
                        if (geminiAdvancedExpanded) {
                            YamabikoTextField(
                                value = responseMimeType,
                                onValueChange = { responseMimeType = it },      
                                label = { Text("Response MIME Type") },
                                placeholder = { Text("例: application/json") },
                                modifier = Modifier.fillMaxWidth()
                            )
                            YamabikoTextField(
                                value = responseJsonSchema,
                                onValueChange = { responseJsonSchema = it },    
                                label = { Text("Response JSON Schema") },
                                placeholder = { Text("{\"type\":\"object\",\"properties\":{...}}") },
                                minLines = 6,
                                maxLines = 12,
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .height(140.dp)
                            )
                            YamabikoTextField(
                                value = functionDeclarations,
                                onValueChange = { functionDeclarations = it },  
                                label = { Text("Function Declarations (JSON Array)") },
                                placeholder = { Text("[{\"name\":\"get_weather\",\"parameters\":{...}}]") },
                                minLines = 6,
                                maxLines = 12,
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .height(140.dp)
                            )
                            Text(
                                text = "空欄の項目は送信されません。JSONが不正な場合は無視されます。",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                }
            }
        }
        if (apiProvider == "SUPERGROK") {
            item {
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
                    border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.6f)),
                    elevation = CardDefaults.cardElevation(defaultElevation = 1.dp)
                ) {
                    Column(
                        modifier = Modifier.padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(16.dp)
                    ) {
                        Text(
                            text = "SuperGrok Settings",
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.SemiBold
                        )
                        Text(
                            text = "Endpoint: ${com.porarri.yamabikochat.data.remote.ProviderCatalog.defaultSuperGrokBaseUrl}",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        SettingsToggleRow(
                            title = "Reasoning",
                            checked = superGrokReasoningEnabled,
                            onCheckedChange = { superGrokReasoningEnabled = it },
                            leadingContent = {
                                Icon(Icons.Default.Psychology, contentDescription = "Reasoning")
                            }
                        )
                        val superGrokEffortLabel = superGrokReasoningEffort.ifBlank { "medium" }
                        YamabikoSelectRow(
                            title = "Reasoning Effort",
                            value = superGrokEffortLabel,
                            enabled = superGrokReasoningEnabled,
                            onClick = { activeSheet = SettingsSheet.SuperGrokReasoningEffort }
                        )
                        Text(
                            text = "SuperGrok / X Premium+ OAuth tokens connect to the xAI API.",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            }
        }
        if (apiProvider == "CODEX_AUTH") {
            item {
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
                    border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.6f)),
                    elevation = CardDefaults.cardElevation(defaultElevation = 1.dp)
                ) {
                    Column(
                        modifier = Modifier.padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(16.dp)
                    ) {
                        Text(
                            text = "Codex Settings",
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.SemiBold
                        )
                        SettingsToggleRow(
                            title = "Reasoning",
                            checked = codexReasoningEnabled,
                            onCheckedChange = { codexReasoningEnabled = it },
                            leadingContent = {
                                Icon(
                                    Icons.Default.Psychology,
                                    contentDescription = "Reasoning"
                                )
                            }
                        )
                        val effortLabel = codexReasoningEffort.ifBlank { "medium" }
                        YamabikoSelectRow(
                            title = "Reasoning Effort",
                            value = effortLabel,
                            enabled = codexReasoningEnabled,
                            onClick = { activeSheet = SettingsSheet.CodexReasoningEffort }
                        )
                        SettingsToggleRow(
                            title = "Prompt Cache",
                            checked = codexPromptCacheEnabled,
                            onCheckedChange = { codexPromptCacheEnabled = it }
                        )
                        if (codexPromptCacheEnabled) {
                            YamabikoTextField(
                                value = codexPromptCacheMinLength.toString(),
                                onValueChange = { v -> v.toIntOrNull()?.let { codexPromptCacheMinLength = it.coerceAtLeast(0) } },
                                label = { Text("Cache min length (chars)") },
                                modifier = Modifier.fillMaxWidth()
                            )
                        }
                        val summaryLabel = codexReasoningSummary.ifBlank { "auto" }
                        YamabikoSelectRow(
                            title = "Reasoning Summary",
                            value = summaryLabel,
                            enabled = codexReasoningEnabled,
                            onClick = { activeSheet = SettingsSheet.CodexReasoningSummary }
                        )
                        SettingsToggleRow(
                            title = "Show Reasoning Summary",
                            checked = codexShowReasoningSummary,
                            enabled = codexReasoningEnabled,
                            onCheckedChange = { codexShowReasoningSummary = it }
                        )
                        SettingsToggleRow(
                            title = "Assume model supports summaries",
                            checked = codexSupportsReasoningSummaries,
                            onCheckedChange = { codexSupportsReasoningSummaries = it }
                        )
                        val verbosityLabel = codexVerbosity.ifBlank { "medium" }
                        YamabikoSelectRow(
                            title = "Verbosity",
                            value = verbosityLabel,
                            onClick = { activeSheet = SettingsSheet.CodexVerbosity }
                        )
                        SettingsToggleRow(
                            title = "Web Search (Codex)",
                            checked = codexWebSearchEnabled,
                            onCheckedChange = { codexWebSearchEnabled = it }
                        )
                        if (codexWebSearchEnabled) {
                            val contextLabel = codexWebSearchContextSize.ifBlank { "medium" }
                            YamabikoSelectRow(
                                title = "Search Context Size",
                                value = contextLabel,
                                onClick = { activeSheet = SettingsSheet.CodexWebSearchContextSize }
                            )
                        }
                    }
                }
            }
        } else {
            item {
                val thinkingLabel = when (apiProvider) {
                    "OPENROUTER" -> "Reasoning"
                    "ZAI" -> "Deep Thinking"
                    else -> "Thinking"
                }
                val isGeminiThinkingLevel = (apiProvider == "GEMINI") &&
                    ModelUtils.isThinkingLevelSupported(model)
                val isAlwaysOn = (apiProvider == "GEMINI") &&
                    ModelUtils.isThinkingAlwaysOn(model)
                val isGeminiThinkingLevelModel = (apiProvider == "GEMINI") &&
                    ModelUtils.isThinkingLevelSupported(model)
                val showBudgetSlider = !isGeminiThinkingLevelModel &&
                    thinkingEnabled &&
                    apiProvider != "ZAI" &&
                    apiProvider != "CODEX_AUTH" &&
                    apiProvider != "SUPERGROK" &&
                    (apiProvider != "OPENROUTER" || reasoningMode == "budget")
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
                    border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.6f)),
                    elevation = CardDefaults.cardElevation(defaultElevation = 1.dp)
                ) {
                    Column(
                        modifier = Modifier.padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(16.dp)
                    ) {
                        Text(
                            text = "Thinking / Reasoning",
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.SemiBold
                        )
                        SettingsToggleRow(
                            title = thinkingLabel,
                            checked = thinkingEnabled,
                            onCheckedChange = { enabled ->
                                thinkingEnabled = enabled
                                if (isGeminiThinkingLevel && !isAlwaysOn) {
                                    val minimal = ModelUtils.getMinimalThinkingLevel(model)
                                    if (!enabled && minimal != null) {
                                        thinkingLevel = minimal
                                    } else if (enabled) {
                                        val defaultLevel = ModelUtils.getDefaultThinkingLevel(model)
                                        if (thinkingLevel.isBlank() || thinkingLevel == minimal) {
                                            thinkingLevel = defaultLevel
                                        }
                                    }
                                }
                            },
                            enabled = !isAlwaysOn,
                            leadingContent = {
                                Icon(
                                    Icons.Default.Psychology,
                                    contentDescription = thinkingLabel
                                )
                            }
                        )
                        if ((apiProvider == "GEMINI") && ModelUtils.isThinkingLevelSupported(model)) {
                            val normalized = ModelUtils.normalizeThinkingLevel(model, thinkingLevel)
                            val selected = normalized ?: ModelUtils.getDefaultThinkingLevel(model)
                            val levelSelectorEnabled = isAlwaysOn || thinkingEnabled
                            val selectedLabel = when (selected) {
                                "minimal" -> "Minimal (ほぼOFF)"
                                "low" -> "Low"
                                "medium" -> "Medium"
                                else -> "\u30B7\u30B9\u30C6\u30E0\u306B\u5F93\u3046"
                            }
                            YamabikoSelectRow(
                                title = "Thinking Level",
                                value = selectedLabel,
                                enabled = levelSelectorEnabled,
                                onClick = { activeSheet = SettingsSheet.ThinkingLevel }
                            )
                        }
                        if (showBudgetSlider) {
                            val label = if (apiProvider == "OPENROUTER") {
                                "Max reasoning tokens: ${thinkingBudget.toInt()}"
                            } else {
                                "Thinking Budget: ${thinkingBudget.toInt()}"
                            }
                            Text(
                                text = label,
                                style = MaterialTheme.typography.bodyLarge,
                                fontWeight = FontWeight.Medium,
                                color = MaterialTheme.colorScheme.onSurface
                            )

                            val optimalRange = if (apiProvider == "GEMINI") {
                                ModelUtils.getThinkingBudgetFloatRange(model) ?: 0f..24576f
                            } else {
                                0f..32000f
                            }
                            val optimalSteps = if (apiProvider == "GEMINI") {
                                ModelUtils.getOptimalThinkingSteps(model)
                            } else {
                                0
                            }

                            Slider(
                                value = thinkingBudget.coerceIn(optimalRange.start, optimalRange.endInclusive),
                                onValueChange = { thinkingBudget = it },
                                valueRange = optimalRange,
                                steps = optimalSteps,
                                enabled = apiProvider != "OPENROUTER" || reasoningMode == "budget"
                            )

                            if (apiProvider == "OPENROUTER") {
                                Text(
                                    "Leave at 0 to let the provider infer a budget. Some models will translate this into an effort level automatically.",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                        }
                    }
                }
            }
        }
        if (apiProvider == "OPENROUTER") {
            openRouterReasoningSection(
                reasoningMode = reasoningMode,
                onReasoningModeChange = { reasoningMode = it },
                reasoningEffort = reasoningEffort,
                onReasoningEffortChange = { reasoningEffort = it },
                reasoningExclude = reasoningExclude,
                onReasoningExcludeChange = { reasoningExclude = it },
                thinkingEnabled = thinkingEnabled
            )
        }
        if (apiProvider == "GEMINI") {
            geminiThinkingInfoSection(model = model)
        }
        item {
            Card(
                modifier = Modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
                border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.6f)),
                elevation = CardDefaults.cardElevation(defaultElevation = 1.dp)
            ) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(16.dp)
                ) {
                    Text(
                        text = "\u30C1\u30E3\u30C3\u30C8\u8A2D\u5B9A",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold
                    )
                    SettingsToggleRow(
                        title = "Streaming",
                        checked = isStreamingEnabled,
                        onCheckedChange = { isStreamingEnabled = it }
                    )
                    SettingsToggleRow(
                        title = "クライアント側Web検索",
                        description = "LLMが必要に応じてWeb検索とページ取得を実行します。外部検索APIキーは不要です。",
                        checked = clientWebSearchToolEnabled,
                        onCheckedChange = {
                            clientWebSearchToolEnabled = it
                            viewModel.updateClientWebSearchToolEnabled(it)
                        }
                    )
                    if (!com.porarri.yamabikochat.data.tools.ClientTools.supportsClientWebSearchTool(apiProvider)) {
                        Text(
                            text = "現在のプロバイダーではこのツールは使用されません。",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.tertiary
                        )
                    }
                    val providerLabel = modelsDevCatalogState.providers.firstOrNull {
                        it.id == ProviderReference(apiProvider).modelsDevId
                    }?.name ?: ProviderCatalog.displayName(apiProvider)
                    val providerKey = apiProvider.uppercase()
                    val showGlobalPresetsForProvider =
                        showGlobalProviderPresetsInChatByProvider[providerKey] ?: showGlobalProviderPresetsInChat
                    SettingsToggleRow(
                        title = "\u30C1\u30E3\u30C3\u30C8\u306E\u30D7\u30EA\u30BB\u30C3\u30C8\u306B\u30B0\u30ED\u30FC\u30D0\u30EB\u8A2D\u5B9A\u3092\u8868\u793A",
                        description = "\u73FE\u5728\u306E\u30D7\u30ED\u30D0\u30A4\u30C0\u30FC\uff08$providerLabel\uff09\u306E\u30B0\u30ED\u30FC\u30D0\u30EB\u8A2D\u5B9A\u3092\u30D7\u30EA\u30BB\u30C3\u30C8\u3068\u3057\u3066\u8FFD\u52A0\u3057\u307E\u3059",
                        checked = showGlobalPresetsForProvider,
                        onCheckedChange = { showGlobalProviderPresetsInChatByProvider[providerKey] = it }
                    )
                }
            }
        }

        modelPresetsSection(
            presets = presets,
            onCreatePreset = { startCreatingPreset() },
            onEditPreset = { startEditingPreset(it) },
            onDeletePreset = { viewModel.deleteModelPreset(it) }
        )
                    }
                    if (selectedTab == 2) {
        dualModeSettingsSection(
            isDualModeEnabled = isDualModeEnabled,
            onDualModeEnabledChange = { enabled ->
                isDualModeEnabled = enabled
                if (enabled) {
                    isAutoConversationEnabled = false
                    isFusionModeEnabled = false
                }
            },
            dualBlockedByFusion = isFusionModeEnabled,
            presetOptions = presetOptions,
            onPresetSelectedA = { applyPresetToDualA(it) },
            onPresetSelectedB = { applyPresetToDualB(it) },
            providerA = dualProviderA,
            onProviderAChange = {
                dualProviderA = it
                if (dualToolsOverrideA) applyDualToolDefaultsA(useOverrides = false)
                if (dualThinkingOverrideA) applyDualThinkingDefaultsA(useOverrides = false)
            },
            modelA = dualModelA,
            onModelAChange = { dualModelA = it },
            selectedProviderA = dualSelectedProviderA,
            onSelectedProviderAChange = { dualSelectedProviderA = it },
            reasoningA = dualReasoningStateA,
            toolsA = dualToolsStateA,
            thinkingA = dualThinkingStateA,
            providerB = dualProviderB,
            onProviderBChange = {
                dualProviderB = it
                if (dualToolsOverrideB) applyDualToolDefaultsB(useOverrides = false)
                if (dualThinkingOverrideB) applyDualThinkingDefaultsB(useOverrides = false)
            },
            modelB = dualModelB,
            onModelBChange = { dualModelB = it },
            selectedProviderB = dualSelectedProviderB,
            onSelectedProviderBChange = { dualSelectedProviderB = it },
            reasoningB = dualReasoningStateB,
            toolsB = dualToolsStateB,
            thinkingB = dualThinkingStateB,
            openRouterModels = openRouterModels,
            openRouterModelsLoading = openRouterModelsLoading,
            openRouterModelsError = openRouterModelsError,
            onRefreshOpenRouterModels = { viewModel.refreshOpenRouterModels() },
            pinnedModelIds = openRouterPinnedModels,
            recentModelIds = openRouterRecentModels,
            onTogglePinned = { toggleOpenRouterPinnedModel(it) },
            onRecentUsed = { registerOpenRouterRecentModel(it) },
            catalogProviders = modelsDevCatalogState.providers,
            dualSplitLayout = dualSplitLayout,
            onDualSplitLayoutChange = { dualSplitLayout = it },
            dualSplitRatio = dualSplitRatio,
            onDualSplitRatioChange = { dualSplitRatio = it }
        )

        autoConversationSettingsSection(
            isAutoConversationEnabled = isAutoConversationEnabled,
            onAutoConversationEnabledChange = { enabled ->
                isAutoConversationEnabled = enabled
                if (enabled) {
                    isDualModeEnabled = false
                    isFusionModeEnabled = false
                }
            },
            autoBlockedByFusion = isFusionModeEnabled,
            presetOptions = presetOptions,
            onPresetSelectedA = { applyPresetToAutoA(it) },
            onPresetSelectedB = { applyPresetToAutoB(it) },
            providerA = autoProviderA,
            onProviderAChange = {
                autoProviderA = it
                if (autoToolsOverrideA) applyAutoToolDefaultsA(useOverrides = false)
                if (autoThinkingOverrideA) applyAutoThinkingDefaultsA(useOverrides = false)
            },
            modelA = autoModelA,
            onModelAChange = { autoModelA = it },
            selectedProviderA = autoSelectedProviderA,
            onSelectedProviderAChange = { autoSelectedProviderA = it },
            systemPromptA = autoSystemPromptA,
            onSystemPromptAChange = { autoSystemPromptA = it },
            reasoningA = autoReasoningStateA,
            toolsA = autoToolsStateA,
            thinkingA = autoThinkingStateA,
            providerB = autoProviderB,
            onProviderBChange = {
                autoProviderB = it
                if (autoToolsOverrideB) applyAutoToolDefaultsB(useOverrides = false)
                if (autoThinkingOverrideB) applyAutoThinkingDefaultsB(useOverrides = false)
            },
            modelB = autoModelB,
            onModelBChange = { autoModelB = it },
            selectedProviderB = autoSelectedProviderB,
            onSelectedProviderBChange = { autoSelectedProviderB = it },
            systemPromptB = autoSystemPromptB,
            onSystemPromptBChange = { autoSystemPromptB = it },
            reasoningB = autoReasoningStateB,
            toolsB = autoToolsStateB,
            thinkingB = autoThinkingStateB,
            maxTurns = autoMaxTurns,
            onMaxTurnsChange = { autoMaxTurns = it },
            openRouterModels = openRouterModels,
            openRouterModelsLoading = openRouterModelsLoading,
            openRouterModelsError = openRouterModelsError,
            onRefreshOpenRouterModels = { viewModel.refreshOpenRouterModels() },
            pinnedModelIds = openRouterPinnedModels,
            recentModelIds = openRouterRecentModels,
            onTogglePinned = { toggleOpenRouterPinnedModel(it) },
            onRecentUsed = { registerOpenRouterRecentModel(it) },
            catalogProviders = modelsDevCatalogState.providers
        )

        fusionModeSettingsSection(
            isFusionModeEnabled = isFusionModeEnabled,
            onFusionModeEnabledChange = { enabled ->
                isFusionModeEnabled = enabled
                if (enabled) {
                    isDualModeEnabled = false
                    isAutoConversationEnabled = false
                }
            },
            fusionBlockedByDualOrAuto = isDualModeEnabled || isAutoConversationEnabled,
            fusionTaskType = fusionTaskType,
            onFusionTaskTypeChange = { fusionTaskType = it },
            fusionDebugModeEnabled = fusionDebugModeEnabled,
            onFusionDebugModeEnabledChange = { fusionDebugModeEnabled = it },
            fusionLogPromptsEnabled = fusionLogPromptsEnabled,
            onFusionLogPromptsEnabledChange = { fusionLogPromptsEnabled = it },
            fusionCustomPresetJSON = fusionCustomPresetJSON,
            onFusionCustomPresetJSONChange = { fusionCustomPresetJSON = it }
        )

        diagnosticsSection(apiKeyStatus)

                }
    }
            }
        }
    }
}
    }
}

@Composable
private fun SettingsHomeContent(
    modifier: Modifier = Modifier,
    onOpenTab: (Int) -> Unit
) {
    LazyColumn(
        modifier = modifier,
        verticalArrangement = Arrangement.spacedBy(24.dp),
        contentPadding = PaddingValues(bottom = 24.dp)
    ) {
        item { SettingsProfileHeader() }

        item {
            Text(
                "変更は自動で保存されます。",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }

        item {
            SettingsHomeSection(title = "My Yamabiko") {
                SettingsHomeRow(
                    icon = Icons.Default.Tune,
                    title = stringResource(R.string.api_model),
                    onClick = { onOpenTab(0) }
                )
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                SettingsHomeRow(
                    icon = Icons.Default.TextFields,
                    title = stringResource(R.string.settings_tab_system_prompt),
                    onClick = { onOpenTab(1) }
                )
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                SettingsHomeRow(
                    icon = Icons.Default.Compare,
                    title = stringResource(R.string.settings_tab_dual_auto_math),
                    onClick = { onOpenTab(2) }
                )
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                SettingsHomeRow(
                    icon = Icons.Default.Palette,
                    title = stringResource(R.string.settings_tab_appearance),
                    onClick = { onOpenTab(3) }
                )
            }
        }
    }
}

@Composable
private fun SettingsProfileHeader() {
    Column(
        modifier = Modifier.fillMaxWidth(),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Surface(
            modifier = Modifier.size(80.dp),
            shape = CircleShape,
            color = MaterialTheme.colorScheme.surfaceContainerHigh
        ) {
            Box(contentAlignment = Alignment.Center) {
                Text(
                    text = "YA",
                    style = MaterialTheme.typography.headlineSmall,
                    fontWeight = FontWeight.SemiBold
                )
            }
        }

        Spacer(modifier = Modifier.height(12.dp))

        Text(
            text = "Yamabiko",
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.SemiBold
        )
        Text(
            text = "local",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

@Composable
private fun SettingsHomeSection(
    title: String,
    content: @Composable ColumnScope.() -> Unit
) {
    Column(modifier = Modifier.fillMaxWidth()) {
        Text(
            text = title,
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold,
            color = MaterialTheme.colorScheme.onSurface,
            modifier = Modifier.padding(horizontal = 4.dp, vertical = 12.dp)
        )
        Spacer(modifier = Modifier.height(4.dp))
        Card(
            modifier = Modifier.fillMaxWidth(),
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
            border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.6f)),
            elevation = CardDefaults.cardElevation(defaultElevation = 1.dp)
        ) {
            Column { content() }
        }
    }
}

@Composable
private fun SettingsHomeRow(
    icon: ImageVector,
    title: String,
    onClick: () -> Unit
) {
    ListItem(
        headlineContent = {
            Text(
                text = title,
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.Medium,
                color = MaterialTheme.colorScheme.onSurface
            )
        },
        leadingContent = { Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.onSurface) },
        trailingContent = {
            Icon(
                Icons.AutoMirrored.Filled.KeyboardArrowRight,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary
            )
        },
        colors = ListItemDefaults.colors(containerColor = MaterialTheme.colorScheme.surface),
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
    )
}

@Composable
private fun LabeledValueBlock(
    label: String,
    value: String,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(2.dp)
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.labelLarge,
            fontWeight = FontWeight.Medium,
            color = MaterialTheme.colorScheme.onSurface
        )
        Text(
            text = value,
            style = MaterialTheme.typography.bodyLarge,
            fontWeight = FontWeight.SemiBold,
            color = MaterialTheme.colorScheme.onSurface
        )
    }
}

@Composable
private fun TokenUsageStatsCard(state: TokenUsageUiState) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.6f)),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp)
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            Text(
                text = "トークン統計（直近${state.rangeDays}日）",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold
            )
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                UsageStatCell(
                    label = "Spend",
                    value = formatUsd(state.totals.totalCostUsd),
                    modifier = Modifier.weight(1f)
                )
                UsageStatCell(
                    label = "Requests",
                    value = formatCompactCount(state.totals.requestCount),
                    modifier = Modifier.weight(1f)
                )
                UsageStatCell(
                    label = "Tokens",
                    value = formatCompactCount(state.totals.totalTokens),
                    modifier = Modifier.weight(1f)
                )
            }
            if (state.daily.isNotEmpty()) {
                TokenUsageMiniBars(state)
            }
            if (state.byModel.isNotEmpty()) {
                Text(
                    text = "Requests By Model",
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold
                )
                val maxTokens = state.byModel.maxOfOrNull { it.totalTokens }?.coerceAtLeast(1L) ?: 1L
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    state.byModel.take(8).forEach { item ->
                        val ratio = (item.totalTokens.toFloat() / maxTokens.toFloat()).coerceIn(0f, 1f)
                        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Text(
                                    text = item.model,
                                    style = MaterialTheme.typography.bodyMedium,
                                    fontWeight = FontWeight.Medium,
                                    modifier = Modifier.weight(1f),
                                    maxLines = 1
                                )
                                Spacer(modifier = Modifier.width(8.dp))
                                Text(
                                    text = "${formatCompactCount(item.requestCount)} req • ${formatCompactCount(item.totalTokens)} tok • ${formatUsd(item.totalCostUsd)}",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                            Box(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .height(4.dp)
                                    .background(MaterialTheme.colorScheme.surfaceContainerHighest, RoundedCornerShape(999.dp))
                            ) {
                                Box(
                                    modifier = Modifier
                                        .fillMaxHeight()
                                        .fillMaxWidth(ratio)
                                        .background(MaterialTheme.colorScheme.primary, RoundedCornerShape(999.dp))
                                )
                            }
                        }
                    }
                }
            } else {
                Text(
                    text = "まだトークン使用履歴がありません。",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

@Composable
private fun UsageStatCell(label: String, value: String, modifier: Modifier = Modifier) {
    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(
            text = label,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Text(
            text = value,
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Bold
        )
    }
}

@Composable
private fun TokenUsageMiniBars(state: TokenUsageUiState) {
    val points = state.daily.takeLast(24)
    val maxTokens = points.maxOfOrNull { it.totalTokens }?.coerceAtLeast(1L) ?: 1L
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(48.dp),
        horizontalArrangement = Arrangement.spacedBy(2.dp),
        verticalAlignment = Alignment.Bottom
    ) {
        points.forEach { point ->
            val ratio = (point.totalTokens.toFloat() / maxTokens.toFloat()).coerceIn(0.08f, 1f)
            Box(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxHeight(ratio)
                    .background(MaterialTheme.colorScheme.primary.copy(alpha = 0.7f), RoundedCornerShape(topStart = 4.dp, topEnd = 4.dp))
            )
        }
    }
}

private fun formatUsd(value: Double): String = String.format(Locale.US, "$%.5f", value)

private fun formatCompactCount(value: Long): String {
    val abs = kotlin.math.abs(value.toDouble())
    return when {
        abs >= 1_000_000_000 -> String.format(Locale.US, "%.1fB", value / 1_000_000_000.0)
        abs >= 1_000_000 -> String.format(Locale.US, "%.1fM", value / 1_000_000.0)
        abs >= 1_000 -> String.format(Locale.US, "%.1fK", value / 1_000.0)
        else -> value.toString()
    }
}

private fun codexUsagePlanLabel(usage: CodexUsageStatus): String? =
    usage.planType?.trim()?.takeIf { it.isNotBlank() }

private fun codexUsageCreditsLabel(usage: CodexUsageStatus): String? {
    val credits = usage.credits ?: return null
    if (!credits.hasCredits) return null
    if (credits.unlimited) return "Unlimited"
    val parsed = credits.balance?.trim()?.toDoubleOrNull()
    if (parsed != null) {
        if (parsed <= 0.0) return null
        return "${parsed.roundToInt()} credits"
    }
    return credits.balance?.trim()?.takeIf { it.isNotBlank() }?.let { "$it credits" }
}

private fun formatCodexRateLimitWindow(window: CodexRateLimitWindow): String {
    val usedPercent = window.usedPercent?.coerceIn(0.0, 100.0)
    val remainingPercent = usedPercent?.let { (100.0 - it).coerceIn(0.0, 100.0) }
    val windowDuration = window.limitWindowSeconds?.let { formatCodexWindowDuration(it) }
    val resetAt = window.resetAtEpochSeconds?.let { epoch ->
        runCatching { Instant.ofEpochSecond(epoch).toString() }.getOrNull()
    }
    val pieces = listOfNotNull(
        usedPercent?.let { "${it.roundToInt()}% used" },
        remainingPercent?.let { "${it.roundToInt()}% left" },
        windowDuration?.let { "window $it" },
        resetAt?.let { "reset $it" }
    )
    return pieces.joinToString(" \u2022 ").ifBlank { "rate limit info unavailable" }
}

private fun formatCodexWindowDuration(seconds: Int): String {
    if (seconds <= 0) return "${seconds}s"
    val minutes = (seconds + 59) / 60
    if (minutes % (24 * 60) == 0) return "${minutes / (24 * 60)}d"
    if (minutes % 60 == 0) return "${minutes / 60}h"
    return "${minutes}m"
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SettingsScreenPreviewContent(initialTab: Int) {
    var selectedTab by rememberSaveable { mutableStateOf(initialTab) }
    val tabs = listOf(
            stringResource(R.string.settings_tab_api),
            stringResource(R.string.settings_tab_system_prompt),
            stringResource(R.string.settings_tab_dual_auto_math),
            stringResource(R.string.settings_tab_appearance)
        )

    var dynamicColorEnabled by remember { mutableStateOf(true) }
    var themeColor by remember { mutableStateOf(ThemeColorPreset.BluePurple.key) }
    var themeMode by remember { mutableStateOf("LIGHT") }

    var apiProvider by remember { mutableStateOf("GEMINI") }
    var apiKeyInput by remember { mutableStateOf("AIza...") }
    var model by remember { mutableStateOf("gemini-3-flash-preview") }

    var googleSearchEnabled by remember { mutableStateOf(true) }
    var urlContextEnabled by remember { mutableStateOf(false) }
    var codeExecutionEnabled by remember { mutableStateOf(false) }
    var googleMapsEnabled by remember { mutableStateOf(false) }
    var computerUseEnabled by remember { mutableStateOf(false) }

    var thinkingEnabled by remember { mutableStateOf(true) }
    var thinkingLevel by remember { mutableStateOf("minimal") }
    var isStreamingEnabled by remember { mutableStateOf(true) }
    var showGlobalProviderPresetsInChat by remember { mutableStateOf(true) }

    var systemPromptPresetName by remember { mutableStateOf("こんにちは") }
    var systemPrompt by remember { mutableStateOf("必ず日本語でかいとうして") }

    var isDualModeEnabled by remember { mutableStateOf(true) }
    var dualProviderA by remember { mutableStateOf("ZAI") }
    var dualModelA by remember { mutableStateOf("glm-5.2") }
    var dualSelectedProviderA by remember { mutableStateOf<String?>(null) }
    var dualProviderB by remember { mutableStateOf("MINIMAX") }
    var dualModelB by remember { mutableStateOf("MiniMax-M2.1") }
    var dualSelectedProviderB by remember { mutableStateOf<String?>(null) }
    var dualSplitLayout by remember { mutableStateOf("VERTICAL") }
    var dualSplitRatio by remember { mutableStateOf(0.5f) }

    var dualOverrideA by remember { mutableStateOf(false) }
    var dualReasonEnabledA by remember { mutableStateOf(true) }
    var dualReasonModeA by remember { mutableStateOf("auto") }
    var dualReasonEffortA by remember { mutableStateOf("medium") }
    var dualReasonExcludeA by remember { mutableStateOf(false) }
    var dualReasonBudgetA by remember { mutableStateOf(0f) }

    var dualOverrideB by remember { mutableStateOf(false) }
    var dualReasonEnabledB by remember { mutableStateOf(true) }
    var dualReasonModeB by remember { mutableStateOf("auto") }
    var dualReasonEffortB by remember { mutableStateOf("medium") }
    var dualReasonExcludeB by remember { mutableStateOf(false) }
    var dualReasonBudgetB by remember { mutableStateOf(0f) }

    val dualReasoningStateA = remember(dualOverrideA, dualReasonEnabledA, dualReasonModeA, dualReasonEffortA, dualReasonExcludeA, dualReasonBudgetA) {
        ReasoningOverrideUiState(
            overrideEnabled = dualOverrideA,
            onOverrideEnabledChange = { dualOverrideA = it },
            reasoningEnabled = dualReasonEnabledA,
            onReasoningEnabledChange = { dualReasonEnabledA = it },
            reasoningMode = dualReasonModeA,
            onReasoningModeChange = { dualReasonModeA = it },
            reasoningEffort = dualReasonEffortA,
            onReasoningEffortChange = { dualReasonEffortA = it },
            reasoningExclude = dualReasonExcludeA,
            onReasoningExcludeChange = { dualReasonExcludeA = it },
            reasoningBudget = dualReasonBudgetA,
            onReasoningBudgetChange = { dualReasonBudgetA = it },
            onApplyDefaults = {}
        )
    }

    val dualReasoningStateB = remember(dualOverrideB, dualReasonEnabledB, dualReasonModeB, dualReasonEffortB, dualReasonExcludeB, dualReasonBudgetB) {
        ReasoningOverrideUiState(
            overrideEnabled = dualOverrideB,
            onOverrideEnabledChange = { dualOverrideB = it },
            reasoningEnabled = dualReasonEnabledB,
            onReasoningEnabledChange = { dualReasonEnabledB = it },
            reasoningMode = dualReasonModeB,
            onReasoningModeChange = { dualReasonModeB = it },
            reasoningEffort = dualReasonEffortB,
            onReasoningEffortChange = { dualReasonEffortB = it },
            reasoningExclude = dualReasonExcludeB,
            onReasoningExcludeChange = { dualReasonExcludeB = it },
            reasoningBudget = dualReasonBudgetB,
            onReasoningBudgetChange = { dualReasonBudgetB = it },
            onApplyDefaults = {}
        )
    }

    val dualToolsStateA = remember {
        ToolingOverrideUiState(
            overrideEnabled = false,
            onOverrideEnabledChange = {},
            googleSearchEnabled = false,
            onGoogleSearchEnabledChange = {},
            codeExecutionEnabled = false,
            onCodeExecutionEnabledChange = {},
            urlContextEnabled = false,
            onUrlContextEnabledChange = {},
            googleMapsEnabled = false,
            onGoogleMapsEnabledChange = {},
            computerUseEnabled = false,
            onComputerUseEnabledChange = {},
            onApplyDefaults = {}
        )
    }

    val dualToolsStateB = remember {
        ToolingOverrideUiState(
            overrideEnabled = false,
            onOverrideEnabledChange = {},
            googleSearchEnabled = false,
            onGoogleSearchEnabledChange = {},
            codeExecutionEnabled = false,
            onCodeExecutionEnabledChange = {},
            urlContextEnabled = false,
            onUrlContextEnabledChange = {},
            googleMapsEnabled = false,
            onGoogleMapsEnabledChange = {},
            computerUseEnabled = false,
            onComputerUseEnabledChange = {},
            onApplyDefaults = {}
        )
    }

    val dualThinkingStateA = remember {
        ThinkingOverrideUiState(
            overrideEnabled = false,
            onOverrideEnabledChange = {},
            thinkingEnabled = true,
            onThinkingEnabledChange = {},
            thinkingBudget = 0f,
            onThinkingBudgetChange = {},
            thinkingLevel = "",
            onThinkingLevelChange = {},
            codexReasoningEffort = "medium",
            onCodexReasoningEffortChange = {},
            onApplyDefaults = {}
        )
    }

    val dualThinkingStateB = remember {
        ThinkingOverrideUiState(
            overrideEnabled = false,
            onOverrideEnabledChange = {},
            thinkingEnabled = true,
            onThinkingEnabledChange = {},
            thinkingBudget = 0f,
            onThinkingBudgetChange = {},
            thinkingLevel = "",
            onThinkingLevelChange = {},
            codexReasoningEffort = "medium",
            onCodexReasoningEffortChange = {},
            onApplyDefaults = {}
        )
    }

    var isAutoConversationEnabled by remember { mutableStateOf(false) }
    var autoProviderA by remember { mutableStateOf("OPENROUTER") }
    var autoModelA by remember { mutableStateOf("deepseek/deepseek-chat") }
    var autoSelectedProviderA by remember { mutableStateOf<String?>(null) }
    var autoSystemPromptA by remember { mutableStateOf("あなたは世界的な小説家です") }
    var autoProviderB by remember { mutableStateOf("GEMINI") }
    var autoModelB by remember { mutableStateOf("gemini-3-flash-preview") }
    var autoSelectedProviderB by remember { mutableStateOf<String?>(null) }
    var autoSystemPromptB by remember { mutableStateOf("続きも書いてください") }
    var autoMaxTurns by remember { mutableStateOf(10) }

    var autoOverrideA by remember { mutableStateOf(false) }
    var autoReasonEnabledA by remember { mutableStateOf(true) }
    var autoReasonModeA by remember { mutableStateOf("auto") }
    var autoReasonEffortA by remember { mutableStateOf("medium") }
    var autoReasonExcludeA by remember { mutableStateOf(false) }
    var autoReasonBudgetA by remember { mutableStateOf(0f) }

    var autoOverrideB by remember { mutableStateOf(false) }
    var autoReasonEnabledB by remember { mutableStateOf(true) }
    var autoReasonModeB by remember { mutableStateOf("auto") }
    var autoReasonEffortB by remember { mutableStateOf("medium") }
    var autoReasonExcludeB by remember { mutableStateOf(false) }
    var autoReasonBudgetB by remember { mutableStateOf(0f) }

    val autoReasoningStateA = remember(autoOverrideA, autoReasonEnabledA, autoReasonModeA, autoReasonEffortA, autoReasonExcludeA, autoReasonBudgetA) {
        ReasoningOverrideUiState(
            overrideEnabled = autoOverrideA,
            onOverrideEnabledChange = { autoOverrideA = it },
            reasoningEnabled = autoReasonEnabledA,
            onReasoningEnabledChange = { autoReasonEnabledA = it },
            reasoningMode = autoReasonModeA,
            onReasoningModeChange = { autoReasonModeA = it },
            reasoningEffort = autoReasonEffortA,
            onReasoningEffortChange = { autoReasonEffortA = it },
            reasoningExclude = autoReasonExcludeA,
            onReasoningExcludeChange = { autoReasonExcludeA = it },
            reasoningBudget = autoReasonBudgetA,
            onReasoningBudgetChange = { autoReasonBudgetA = it },
            onApplyDefaults = {}
        )
    }

    val autoReasoningStateB = remember(autoOverrideB, autoReasonEnabledB, autoReasonModeB, autoReasonEffortB, autoReasonExcludeB, autoReasonBudgetB) {
        ReasoningOverrideUiState(
            overrideEnabled = autoOverrideB,
            onOverrideEnabledChange = { autoOverrideB = it },
            reasoningEnabled = autoReasonEnabledB,
            onReasoningEnabledChange = { autoReasonEnabledB = it },
            reasoningMode = autoReasonModeB,
            onReasoningModeChange = { autoReasonModeB = it },
            reasoningEffort = autoReasonEffortB,
            onReasoningEffortChange = { autoReasonEffortB = it },
            reasoningExclude = autoReasonExcludeB,
            onReasoningExcludeChange = { autoReasonExcludeB = it },
            reasoningBudget = autoReasonBudgetB,
            onReasoningBudgetChange = { autoReasonBudgetB = it },
            onApplyDefaults = {}
        )
    }

    val autoToolsStateA = remember {
        ToolingOverrideUiState(
            overrideEnabled = false,
            onOverrideEnabledChange = {},
            googleSearchEnabled = false,
            onGoogleSearchEnabledChange = {},
            codeExecutionEnabled = false,
            onCodeExecutionEnabledChange = {},
            urlContextEnabled = false,
            onUrlContextEnabledChange = {},
            googleMapsEnabled = false,
            onGoogleMapsEnabledChange = {},
            computerUseEnabled = false,
            onComputerUseEnabledChange = {},
            onApplyDefaults = {}
        )
    }

    val autoToolsStateB = remember {
        ToolingOverrideUiState(
            overrideEnabled = false,
            onOverrideEnabledChange = {},
            googleSearchEnabled = false,
            onGoogleSearchEnabledChange = {},
            codeExecutionEnabled = false,
            onCodeExecutionEnabledChange = {},
            urlContextEnabled = false,
            onUrlContextEnabledChange = {},
            googleMapsEnabled = false,
            onGoogleMapsEnabledChange = {},
            computerUseEnabled = false,
            onComputerUseEnabledChange = {},
            onApplyDefaults = {}
        )
    }

    val autoThinkingStateA = remember {
        ThinkingOverrideUiState(
            overrideEnabled = false,
            onOverrideEnabledChange = {},
            thinkingEnabled = true,
            onThinkingEnabledChange = {},
            thinkingBudget = 0f,
            onThinkingBudgetChange = {},
            thinkingLevel = "",
            onThinkingLevelChange = {},
            codexReasoningEffort = "medium",
            onCodexReasoningEffortChange = {},
            onApplyDefaults = {}
        )
    }

    val autoThinkingStateB = remember {
        ThinkingOverrideUiState(
            overrideEnabled = false,
            onOverrideEnabledChange = {},
            thinkingEnabled = true,
            onThinkingEnabledChange = {},
            thinkingBudget = 0f,
            onThinkingBudgetChange = {},
            thinkingLevel = "",
            onThinkingLevelChange = {},
            codexReasoningEffort = "medium",
            onCodexReasoningEffortChange = {},
            onApplyDefaults = {}
        )
    }

    var mathRenderingEnabled by remember { mutableStateOf(true) }

    val presetOptions = remember {
        listOf(
            ModelPreset(
                id = 1L,
                name = "Google Gemini",
                model = "gemini-3-flash-preview",
                systemPrompt = null,
                apiProvider = "GEMINI"
            ),
            ModelPreset(
                id = 2L,
                name = "OpenRouter (DeepSeek)",
                model = "deepseek/deepseek-chat",
                systemPrompt = "あなたは丁寧なアシスタントです。",
                apiProvider = "OPENROUTER"
            )
        )
    }

    val openRouterModels = remember {
        listOf(
            SimpleModel(
                id = "deepseek/deepseek-chat",
                name = "DeepSeek Chat",
                provider = "deepseek",
                contextLength = 32_000,
                promptPricePerMillion = 0.14,
                completionPricePerMillion = 0.28,
                isFree = false
            ),
            SimpleModel(
                id = "openai/gpt-4o-mini",
                name = "GPT-4o mini",
                provider = "openai",
                contextLength = 128_000,
                promptPricePerMillion = 0.15,
                completionPricePerMillion = 0.60,
                isFree = false
            ),
            SimpleModel(
                id = "google/gemini-2.5-flash",
                name = "Gemini 2.5 Flash",
                provider = "google",
                contextLength = 1_000_000,
                promptPricePerMillion = 0.0,
                completionPricePerMillion = 0.0,
                isFree = true
            )
        )
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("設定") },
                navigationIcon = {
                    IconButton(onClick = {}) {
                        Icon(Icons.Default.Menu, contentDescription = "Menu")
                    }
                }
            )
        },
        containerColor = MaterialTheme.colorScheme.surfaceVariant
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(horizontal = 16.dp, vertical = 16.dp)
        ) {
            ScrollableTabRow(selectedTabIndex = selectedTab, edgePadding = 0.dp) {
                tabs.forEachIndexed { index, title ->
                    Tab(
                        selected = selectedTab == index,
                        onClick = { selectedTab = index },
                        text = { Text(title) }
                    )
                }
            }

            Spacer(modifier = Modifier.height(12.dp))

            LazyColumn(
                modifier = Modifier
                    .fillMaxWidth()
                    .weight(1f),
                verticalArrangement = Arrangement.spacedBy(24.dp)
            ) {
                when (selectedTab) {
                    3 -> {
                        item {
                            Card(
                                modifier = Modifier.fillMaxWidth(),
                                colors = CardDefaults.cardColors(
                                    containerColor = MaterialTheme.colorScheme.surface
                                ),
                                border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.6f)),
                                elevation = CardDefaults.cardElevation(defaultElevation = 1.dp)
                            ) {
                                Column(
                                    modifier = Modifier.padding(16.dp),
                                    verticalArrangement = Arrangement.spacedBy(16.dp)
                                ) {
                                    Text(
                                        text = "\u5916\u898B",
                                        style = MaterialTheme.typography.titleMedium,
                                        fontWeight = FontWeight.SemiBold
                                    )
                                    Text(
                                        text = "\u5916\u898B\u306E\u8272\u3092\u9078\u629E\u3067\u304D\u307E\u3059\u3002Dynamic Color\u306FAndroid 12\u4EE5\u964D\u3067\u7AEF\u672B\u306E\u914D\u8272\u306B\u5408\u308F\u305B\u307E\u3059\u3002",
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                    val themeColorLabel =
                                        if (dynamicColorEnabled) "Dynamic Color" else ThemeColorPreset.fromKey(themeColor).label
                                    YamabikoSelectRow(
                                        title = "\u5916\u898B\u306E\u8272",
                                        value = themeColorLabel,
                                        onClick = {},
                                        leadingContent = {
                                            Icon(Icons.Default.Palette, contentDescription = null)
                                        }
                                    )
                                    val themeLabel = when (themeMode) {
                                        "LIGHT" -> "\u30E9\u30A4\u30C8"
                                        "DARK" -> "\u30C0\u30FC\u30AF"
                                        else -> "\u30B7\u30B9\u30C6\u30E0\u306B\u5F93\u3046"
                                    }
                                    YamabikoSelectRow(
                                        title = "\u30C6\u30FC\u30DE",
                                        value = themeLabel,
                                        onClick = {}
                                    )
                                }
                            }
                        }
                        mathRenderingSettingsSection(
                            mathRenderingEnabled = mathRenderingEnabled,
                            onMathRenderingChange = { mathRenderingEnabled = it }
                        )
                    }

                    0 -> {
                        item {
                            Card(
                                modifier = Modifier.fillMaxWidth(),
                                colors = CardDefaults.cardColors(
                                    containerColor = MaterialTheme.colorScheme.surface
                                ),
                                border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.6f)),
                                elevation = CardDefaults.cardElevation(defaultElevation = 1.dp)
                            ) {
                                Column(
                                    modifier = Modifier.padding(16.dp),
                                    verticalArrangement = Arrangement.spacedBy(16.dp)
                                ) {
                                    Text(
                                        text = "APIプロバイダー",
                                        style = MaterialTheme.typography.titleMedium,
                                        fontWeight = FontWeight.SemiBold
                                    )
                                    val providerLabel = when (apiProvider) {
                                        "GEMINI" -> "Google Gemini"
                                        "OPENROUTER" -> "OpenRouter"
                                        "MINIMAX" -> "MiniMax"
                                        "ZAI" -> "Z.ai Coding Plan"
                                        "OPENAI" -> "OpenAI"
                                        "CODEX_AUTH" -> "Codex Auth"
                                        "SUPERGROK" -> "SuperGrok"
                                        "OPENAI_COMPAT" -> "OpenAI (Custom)"
                                        else -> apiProvider
                                    }
                                    YamabikoSelectRow(
                                        title = "API Provider",
                                        value = providerLabel,
                                        onClick = {}
                                    )
                                }
                            }
                        }

                        item {
                            Card(
                                modifier = Modifier.fillMaxWidth(),
                                colors = CardDefaults.cardColors(
                                    containerColor = MaterialTheme.colorScheme.surface
                                ),
                                border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.6f)),
                                elevation = CardDefaults.cardElevation(defaultElevation = 1.dp)
                            ) {
                                Column(
                                    modifier = Modifier.padding(16.dp),
                                    verticalArrangement = Arrangement.spacedBy(16.dp)
                                ) {
                                    Text(
                                        text = "APIキー",
                                        style = MaterialTheme.typography.titleMedium,
                                        fontWeight = FontWeight.SemiBold
                                    )
                                    YamabikoTextField(
                                        value = apiKeyInput,
                                        onValueChange = { apiKeyInput = it },
                                        label = { Text("API Key") },
                                        modifier = Modifier.fillMaxWidth(),
                                        visualTransformation = PasswordVisualTransformation()
                                    )
                                }
                            }
                        }

                        item {
                            Card(
                                modifier = Modifier.fillMaxWidth(),
                                colors = CardDefaults.cardColors(
                                    containerColor = MaterialTheme.colorScheme.surface
                                ),
                                border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.6f)),
                                elevation = CardDefaults.cardElevation(defaultElevation = 1.dp)
                            ) {
                                Column(
                                    modifier = Modifier.padding(16.dp),
                                    verticalArrangement = Arrangement.spacedBy(16.dp)
                                ) {
                                    Text(
                                        text = "Model",
                                        style = MaterialTheme.typography.titleMedium,
                                        fontWeight = FontWeight.SemiBold
                                    )
                                    YamabikoTextField(
                                        value = model,
                                        onValueChange = { model = it },
                                        label = { Text("Model") },
                                        modifier = Modifier.fillMaxWidth()
                                    )
                                }
                            }
                        }

                        item {
                            Card(
                                modifier = Modifier.fillMaxWidth(),
                                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
                                border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.6f)),
                                elevation = CardDefaults.cardElevation(defaultElevation = 1.dp)
                            ) {
                                Column(
                                    modifier = Modifier.padding(16.dp),
                                    verticalArrangement = Arrangement.spacedBy(16.dp)
                                ) {
                                    Text(
                                        text = "Gemini Tools",
                                        style = MaterialTheme.typography.titleMedium,
                                        fontWeight = FontWeight.SemiBold
                                    )
                                    SettingsToggleRow(
                                        title = "Google Search",
                                        description = "最新情報の検索に利用します",
                                        checked = googleSearchEnabled,
                                        onCheckedChange = { googleSearchEnabled = it },
                                        leadingContent = { Icon(Icons.Default.Search, contentDescription = null) }
                                    )
                                    SettingsToggleRow(
                                        title = "URL Context",
                                        description = "URLを参照してコンテキストを取得します",
                                        checked = urlContextEnabled,
                                        onCheckedChange = { urlContextEnabled = it },
                                        leadingContent = { Icon(Icons.Default.Link, contentDescription = null) }
                                    )
                                    SettingsToggleRow(
                                        title = "Code Execution",
                                        description = "コード実行ツールを利用します",
                                        checked = codeExecutionEnabled,
                                        onCheckedChange = { codeExecutionEnabled = it },
                                        leadingContent = { Icon(Icons.Default.Code, contentDescription = null) }
                                    )
                                    SettingsToggleRow(
                                        title = "Google Maps",
                                        description = "場所情報の取得に利用します",
                                        checked = googleMapsEnabled,
                                        onCheckedChange = { googleMapsEnabled = it },
                                        leadingContent = { Icon(Icons.Default.Map, contentDescription = null) }
                                    )
                                    SettingsToggleRow(
                                        title = "Computer Use",
                                        description = "ブラウザ/操作系ツールを利用します",
                                        checked = computerUseEnabled,
                                        onCheckedChange = { computerUseEnabled = it },
                                        leadingContent = { Icon(Icons.Default.DesktopWindows, contentDescription = null) }
                                    )
                                }
                            }
                        }

                        item {
                            val thinkingLabel = when (apiProvider) {
                                "OPENROUTER" -> "Reasoning"
                                "ZAI" -> "Deep Thinking"
                                "GEMINI" -> "Thinking"
                                else -> "\u30B7\u30B9\u30C6\u30E0\u306B\u5F93\u3046"
                            }
                            SettingsToggleRow(
                                title = thinkingLabel,
                                checked = thinkingEnabled,
                                onCheckedChange = { thinkingEnabled = it },
                                leadingContent = { Icon(Icons.Default.Psychology, contentDescription = null) }
                            )
                            Spacer(modifier = Modifier.height(8.dp))
                            YamabikoSelectRow(
                                title = "Thinking Level",
                                value = thinkingLevel,
                                onClick = {}
                            )
                        }

                        item {
                            SettingsToggleRow(
                                title = "Streaming",
                                checked = isStreamingEnabled,
                                onCheckedChange = { isStreamingEnabled = it }
                            )
                        }

                        item {
                            SettingsToggleRow(
                                title = "チャットのプリセットにグローバル設定を表示",
                                description = "現在のプロバイダーのグローバル設定をプリセットとして追加します",
                                checked = showGlobalProviderPresetsInChat,
                                onCheckedChange = { showGlobalProviderPresetsInChat = it }
                            )
                        }
                    }

                    1 -> {
                        item {
                            Column(
                                modifier = Modifier.fillMaxWidth(),
                                verticalArrangement = Arrangement.spacedBy(8.dp)
                            ) {
                                YamabikoSelectRow(
                                    title = "System Prompt Preset",
                                    value = systemPromptPresetName,
                                    onClick = {}
                                )
                                YamabikoTextField(
                                    value = systemPromptPresetName,
                                    onValueChange = { systemPromptPresetName = it },
                                    label = { Text("Preset Name") },
                                    modifier = Modifier.fillMaxWidth()
                                )
                                YamabikoTextField(
                                    value = systemPrompt,
                                    onValueChange = { systemPrompt = it },
                                    label = { Text("System Prompt") },
                                    minLines = 6,
                                    maxLines = 12,
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .height(140.dp)
                                )
                            }
                        }
                    }

                    else -> {
                        dualModeSettingsSection(
                            isDualModeEnabled = isDualModeEnabled,
                            onDualModeEnabledChange = { isDualModeEnabled = it },
                            presetOptions = presetOptions,
                            onPresetSelectedA = {},
                            onPresetSelectedB = {},
                            providerA = dualProviderA,
                            onProviderAChange = { dualProviderA = it },
                            modelA = dualModelA,
                            onModelAChange = { dualModelA = it },
                            selectedProviderA = dualSelectedProviderA,
                            onSelectedProviderAChange = { dualSelectedProviderA = it },
                            reasoningA = dualReasoningStateA,
                            toolsA = dualToolsStateA,
                            thinkingA = dualThinkingStateA,
                            providerB = dualProviderB,
                            onProviderBChange = { dualProviderB = it },
                            modelB = dualModelB,
                            onModelBChange = { dualModelB = it },
                            selectedProviderB = dualSelectedProviderB,
                            onSelectedProviderBChange = { dualSelectedProviderB = it },
                            reasoningB = dualReasoningStateB,
                            toolsB = dualToolsStateB,
                            thinkingB = dualThinkingStateB,
                            openRouterModels = openRouterModels,
                            openRouterModelsLoading = false,
                            openRouterModelsError = null,
                            onRefreshOpenRouterModels = {},
                            pinnedModelIds = emptyList(),
                            recentModelIds = emptyList(),
                            onTogglePinned = {},
                            onRecentUsed = {},
                            dualSplitLayout = dualSplitLayout,
                            onDualSplitLayoutChange = { dualSplitLayout = it },
                            dualSplitRatio = dualSplitRatio,
                            onDualSplitRatioChange = { dualSplitRatio = it }
                        )

                        autoConversationSettingsSection(
                            isAutoConversationEnabled = isAutoConversationEnabled,
                            onAutoConversationEnabledChange = { isAutoConversationEnabled = it },
                            presetOptions = presetOptions,
                            onPresetSelectedA = {},
                            onPresetSelectedB = {},
                            providerA = autoProviderA,
                            onProviderAChange = { autoProviderA = it },
                            modelA = autoModelA,
                            onModelAChange = { autoModelA = it },
                            selectedProviderA = autoSelectedProviderA,
                            onSelectedProviderAChange = { autoSelectedProviderA = it },
                            systemPromptA = autoSystemPromptA,
                            onSystemPromptAChange = { autoSystemPromptA = it },
                            reasoningA = autoReasoningStateA,
                            toolsA = autoToolsStateA,
                            thinkingA = autoThinkingStateA,
                            providerB = autoProviderB,
                            onProviderBChange = { autoProviderB = it },
                            modelB = autoModelB,
                            onModelBChange = { autoModelB = it },
                            selectedProviderB = autoSelectedProviderB,
                            onSelectedProviderBChange = { autoSelectedProviderB = it },
                            systemPromptB = autoSystemPromptB,
                            onSystemPromptBChange = { autoSystemPromptB = it },
                            reasoningB = autoReasoningStateB,
                            toolsB = autoToolsStateB,
                            thinkingB = autoThinkingStateB,
                            maxTurns = autoMaxTurns,
                            onMaxTurnsChange = { autoMaxTurns = it },
                            openRouterModels = openRouterModels,
                            openRouterModelsLoading = false,
                            openRouterModelsError = null,
                            onRefreshOpenRouterModels = {},
                            pinnedModelIds = emptyList(),
                            recentModelIds = emptyList(),
                            onTogglePinned = {},
                            onRecentUsed = {}
                        )

                        diagnosticsSection(ApiKeyStatus(hasGeminiKey = true))
                    }
                }
            }
        }
    }
}

@Preview(showBackground = true, name = "Settings - API")
@Composable
private fun SettingsScreenPreviewApi() {
    YamabikoPreview { SettingsScreenPreviewContent(initialTab = 0) }
}

@Preview(showBackground = true, name = "Settings - System Prompt")
@Composable
private fun SettingsScreenPreviewSystemPrompt() {
    YamabikoPreview { SettingsScreenPreviewContent(initialTab = 1) }
}

@Preview(showBackground = true, name = "Settings - Dual/Auto")
@Composable
private fun SettingsScreenPreviewDual() {
    YamabikoPreview { SettingsScreenPreviewContent(initialTab = 2) }
}

@Preview(showBackground = true, name = "Settings - Appearance")
@Composable
private fun SettingsScreenPreviewAppearance() {
    YamabikoPreview { SettingsScreenPreviewContent(initialTab = 3) }
}
