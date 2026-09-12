import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:transcript_core/transcript_core.dart';

import '../gemma/gemma_model_sheet.dart';
import '../recording/recording_controller.dart';
import '../screens/about_screen.dart';
import '../screens/privacy_screen.dart';
import '../whisper/whisper_model_sheet.dart';
import 'connection_test_controller.dart';
import 'local_discovery_sheet.dart';
import 'provider_config.dart';
import 'secure_key_store.dart';
import 'template_manager_screen.dart';
import 'workflow_settings_screen.dart';
import '../screens/backup_screen.dart';
import '../screens/audio_diagnostics_screen.dart';
import 'accessibility_screen.dart';

/// Where the two provider slots are chosen and proven.
///
/// Two independent slots, because transcription and structuring are different jobs with
/// different providers. The header states plainly what the current pairing does with a
/// recording — that claim is the whole point of the app, and stating which configuration
/// is in force is the difference between a privacy feature and privacy marketing.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _transcriptionSection = GlobalKey<_StageSectionState>();
  final _structuringSection = GlobalKey<_StageSectionState>();

  // SharedPreferences has no change stream, so a section that persists a choice asks for
  // a rebuild — build() re-reads SettingsStore.posture, which is a live getter, so the
  // header reflects the freshly written store. Nothing more than a rebuild is needed:
  // this used to also bump a counter used as the ListView's key, which replaced the whole
  // scrollable on every keystroke and sent the scroll position back to the top.
  void _onChanged() => setState(() {});

  // Everything here autosaves already; this exists so a new user has a plain, explicit
  // action to press. It also covers the one field that does not autosave on every
  // keystroke — a pasted API key otherwise commits only when "Test connection" is
  // pressed, so a key typed and never tested would be silently lost without this.
  Future<void> _saveAll() async {
    final transcriptionKeyAdded =
        await _transcriptionSection.currentState?.saveExplicitly() ?? false;
    final structuringKeyAdded =
        await _structuringSection.currentState?.saveExplicitly() ?? false;
    if (transcriptionKeyAdded) {
      await _transcriptionSection.currentState?.discoverModels();
    }
    if (structuringKeyAdded) {
      await _structuringSection.currentState?.discoverModels();
    }
    if (!mounted) return;
    _onChanged();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Settings saved')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsStoreProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('AI providers')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _PostureHeader(posture: settings.posture),
          _StageSection(
              key: _transcriptionSection,
              stage: ProviderStage.transcription,
              onChanged: _onChanged),
          const Divider(height: 32),
          _StageSection(
              key: _structuringSection,
              stage: ProviderStage.structuring,
              onChanged: _onChanged),
          const Divider(height: 32),
          _RecordingsLocationTile(onChanged: _onChanged),
          const Divider(height: 32),
          ListTile(
            leading: const Icon(Icons.tune),
            title: const Text('Workflow features'),
            subtitle: const Text(
              'Meetings, speakers, imports, languages, history, and study aids',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                  builder: (_) => const WorkflowSettingsScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('Note templates'),
            subtitle:
                const Text('Save reusable instructions for structured notes'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                  builder: (_) => const TemplateManagerScreen()),
            ),
          ),
          const Divider(height: 32),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('Privacy'),
            subtitle: const Text(
              'What is stored, what leaves the device, and the crash reports held here',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const PrivacyScreen()),
            ),
          ),
          SwitchListTile.adaptive(
            secondary: const Icon(Icons.delete_sweep_outlined),
            title: const Text('Delete source audio after processing'),
            subtitle: const Text(
                'Keep notes and transcripts, remove original audio.'),
            value: settings.autoDeleteSourceAudio,
            onChanged: (value) async {
              await settings.setAutoDeleteSourceAudio(value);
              _onChanged();
            },
          ),
          if (Platform.isLinux)
            ListTile(
              leading: const Icon(Icons.mic_none),
              title: const Text('Linux audio diagnostics'),
              subtitle: const Text('Inspect PipeWire and input devices'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                    builder: (_) => const AudioDiagnosticsScreen()),
              ),
            ),
          ListTile(
            leading: const Icon(Icons.accessibility_new),
            title: const Text('Accessibility and updates'),
            subtitle: const Text(
                'Contrast, text size, release channel, and benchmarks'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                  builder: (_) => const AccessibilityScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.https_outlined),
            title: const Text('Encrypted device backup'),
            subtitle: const Text('Move notes and transcripts between devices'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const BackupScreen()),
            ),
          ),
          const Divider(height: 32),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('About'),
            subtitle: const Text(
              'App version and information',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const AboutScreen()),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            onPressed: _saveAll,
            child: const Text('Save'),
          ),
        ),
      ),
    );
  }
}

/// Where new recordings are written. Picking a folder only changes what happens next —
/// nothing already saved is moved, so a change here can never lose a recording.
class _RecordingsLocationTile extends ConsumerWidget {
  const _RecordingsLocationTile({required this.onChanged});

  final VoidCallback onChanged;

  Future<void> _choose(BuildContext context, WidgetRef ref) async {
    final chosen = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choose where recordings are saved',
    );
    if (chosen == null || !context.mounted) return;

    await ref.read(settingsStoreProvider).setRecordingsDirPath(chosen);
    onChanged();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text(
        "New recordings will be saved here. Existing recordings won't be moved.",
      ),
    ));
  }

  Future<void> _resetToDefault(BuildContext context, WidgetRef ref) async {
    await ref.read(settingsStoreProvider).setRecordingsDirPath(null);
    onChanged();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = ref.watch(settingsStoreProvider).recordingsDirPath;

    return ListTile(
      leading: const Icon(Icons.folder_outlined),
      title: const Text('Recordings location'),
      subtitle: Text(path ?? 'On this device (default)'),
      trailing: path == null
          ? const Icon(Icons.chevron_right)
          : IconButton(
              icon: const Icon(Icons.restore),
              tooltip: 'Use the default location',
              onPressed: () => _resetToDefault(context, ref),
            ),
      onTap: () => _choose(context, ref),
    );
  }
}

/// Says, in the user's terms, what happens to a recording under the current pairing.
class _PostureHeader extends StatelessWidget {
  const _PostureHeader({required this.posture});

  final ConfigurationPosture posture;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, tone) = switch (posture.posture) {
      DataPosture.onDevice => (Icons.phone_iphone, theme.colorScheme.primary),
      DataPosture.localNetwork => (Icons.wifi, theme.colorScheme.primary),
      DataPosture.cloud => (Icons.cloud_outlined, theme.colorScheme.tertiary),
    };

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: posture.posture == DataPosture.cloud
            ? theme.colorScheme.tertiaryContainer
            : theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: tone),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(posture.summary, style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(
                  posture.detail,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StageSection extends ConsumerStatefulWidget {
  const _StageSection(
      {super.key, required this.stage, required this.onChanged});

  final ProviderStage stage;

  /// Called whenever a persisted choice changes, so the posture header can refresh.
  final VoidCallback onChanged;

  @override
  ConsumerState<_StageSection> createState() => _StageSectionState();
}

class _StageSectionState extends ConsumerState<_StageSection> {
  late ProviderKind _kind;
  final _keyController = TextEditingController();
  final _endpointController = TextEditingController();
  final _modelController = TextEditingController();
  bool _keySaved = false;

  SettingsStore get _store => ref.read(settingsStoreProvider);

  @override
  void initState() {
    super.initState();
    // Restore what was chosen last time, rather than resetting to the first option and
    // silently discarding a configured provider on every visit. A saved kind that is no
    // longer offered for this stage (for example, a transcription option retired since
    // it was picked) falls back to the default rather than selecting nothing.
    final saved = _store.kindFor(widget.stage);
    final offered = ProviderKind.forStage(widget.stage);
    _kind = (saved != null && offered.contains(saved))
        ? saved
        : (widget.stage == ProviderStage.transcription
            ? SettingsStore.defaultTranscription
            : offered.first);
    _endpointController.text = _store.endpointFor(_kind) ?? '';
    _modelController.text = _store.modelFor(_kind) ?? '';
    _refreshKeyState();
  }

  @override
  void dispose() {
    _keyController.dispose();
    _endpointController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  Future<void> _refreshKeyState() async {
    final saved = await ref.read(keyStoreProvider).has(_kind.id);
    if (mounted) setState(() => _keySaved = saved);
  }

  ProviderSelection get _selection => ProviderSelection(
        kind: _kind,
        hasKey: _keySaved || _keyController.text.isNotEmpty,
        model: _modelController.text.trim().isEmpty
            ? null
            : _modelController.text.trim(),
        endpoint: _endpointController.text.trim().isEmpty
            ? null
            : _endpointController.text.trim(),
      );

  Future<void> _persist() async {
    await _store.setKind(widget.stage, _kind);
    if (_endpointController.text.trim().isNotEmpty) {
      await _store.setEndpoint(_kind, _endpointController.text.trim());
    }
    if (_modelController.text.trim().isNotEmpty) {
      await _store.setModel(_kind, _modelController.text.trim());
    }
    widget.onChanged();
  }

  Future<void> _selectKind(ProviderKind value) async {
    setState(() => _kind = value);
    _endpointController.text = _store.endpointFor(value) ?? '';
    _modelController.text = _store.modelFor(value) ?? '';
    ref.read(connectionTestProvider(widget.stage).notifier).reset();
    await _refreshKeyState();
    // Persist the choice immediately: a provider selected but not saved is the exact
    // gap that let a configured app record with nothing set.
    await _store.setKind(widget.stage, value);
    widget.onChanged();
  }

  /// Writes whatever is in this section right now: a typed key (the one field that does
  /// not autosave as it's typed), plus the kind/endpoint/model persisted the normal way.
  /// Used by both "Test connection" and the settings screen's explicit Save button.
  Future<bool> saveExplicitly() async {
    final key = _keyController.text.trim();
    var keyAdded = false;
    if (key.isNotEmpty) {
      await ref.read(keyStoreProvider).write(_kind.id, key);
      _keyController.clear();
      await _refreshKeyState();
      keyAdded = true;
    }
    await _persist();
    return keyAdded;
  }

  Future<void> _test() async {
    await saveExplicitly();
    await discoverModels();
  }

  Future<void> discoverModels() => ref
      .read(connectionTestProvider(widget.stage).notifier)
      .run(_selection, widget.stage);

  String _whisperModelLabel() {
    final id = _modelController.text.trim().isEmpty
        ? WhisperCatalog.recommended.id
        : _modelController.text.trim();
    return WhisperCatalog.byId(id)?.label ?? id;
  }

  Future<void> _pickWhisperModel() async {
    final chosen = await showWhisperModelPicker(
      context,
      selectedModelId: _modelController.text.trim().isEmpty
          ? WhisperCatalog.recommended.id
          : _modelController.text.trim(),
    );
    if (chosen == null || !mounted) return;
    setState(() => _modelController.text = chosen);
    await _persist();
  }

  String _gemmaModelLabel() => _store.gemmaModelFileName ?? 'None chosen yet';

  Future<void> _pickGemmaModel() async {
    final picked = await showGemmaModelPicker(
      context,
      engine: ref.read(gemmaEngineProvider),
    );
    if (picked == null || !mounted) return;
    setState(() {});
  }

  Future<void> _find() async {
    final server = await findLocalServer(context);
    if (server == null || !mounted) return;

    setState(() {
      _endpointController.text = server.baseUrl.toString();
      // Discovery already knows which models the server has; pick the first so the user
      // is not left guessing a name the server would then reject.
      if (server.models.isNotEmpty && _modelController.text.trim().isEmpty) {
        _modelController.text = server.models.first;
      }
      // A discovered server tells us its flavor; align the selected kind so the right
      // adapter and the right context-window lookup are used.
      _kind = server.flavor == LocalFlavor.ollama
          ? ProviderKind.ollama
          : ProviderKind.lmStudio;
    });
    await _persist();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(connectionTestProvider(widget.stage));
    final options = ProviderKind.forStage(widget.stage);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(widget.stage.label.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                  letterSpacing: 1.2, color: theme.colorScheme.primary)),
        ),
        RadioGroup<ProviderKind>(
          groupValue: _kind,
          onChanged: (value) {
            if (value != null) unawaited(_selectKind(value));
          },
          child: Column(
            children: [
              for (final option in options)
                RadioListTile<ProviderKind>(
                  value: option,
                  title: Text(option.label),
                  subtitle: Text(option.subtitle),
                ),
            ],
          ),
        ),
        if (_kind.needsEndpoint) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _endpointController,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    onChanged: (_) => unawaited(_persist()),
                    decoration: InputDecoration(
                      labelText: 'Address',
                      hintText:
                          'http://192.168.1.50:${_kind == ProviderKind.ollama ? 11434 : 1234}',
                      helperText:
                          'The computer running it must be on this network.',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: _find,
                  icon: const Icon(Icons.wifi_find, size: 18),
                  label: const Text('Find'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: TextField(
              controller: _modelController,
              autocorrect: false,
              onChanged: (_) => unawaited(_persist()),
              decoration: const InputDecoration(
                labelText: 'Model',
                hintText: 'llama3.1:8b',
                helperText: 'The model loaded in the server.',
                border: OutlineInputBorder(),
              ),
            ),
          ),
        ],
        if (_kind == ProviderKind.whisperOffline)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Model: ${_whisperModelLabel()}',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: _pickWhisperModel,
                  icon: const Icon(Icons.download_outlined, size: 18),
                  label: const Text('Choose model'),
                ),
              ],
            ),
          ),
        if (_kind == ProviderKind.gemmaOnDevice)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Model: ${_gemmaModelLabel()}',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: _pickGemmaModel,
                  icon: const Icon(Icons.folder_open_outlined, size: 18),
                  label: const Text('Choose model file'),
                ),
              ],
            ),
          ),
        if (_kind.needsKey)
          _CloudModelPicker(
            state: state,
            selectedModel: _modelController.text.trim(),
            onChanged: _selectModel,
          ),
        if (_kind.needsKey)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              controller: _keyController,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              onSubmitted: (_) => unawaited(_test()),
              decoration: InputDecoration(
                labelText: 'API key',
                hintText: _keySaved ? 'A key is saved' : 'Paste your key',
                suffixIcon: _keySaved
                    ? IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: 'Remove saved key',
                        onPressed: () async {
                          await ref.read(keyStoreProvider).delete(_kind.id);
                          await _refreshKeyState();
                          widget.onChanged();
                        },
                      )
                    : null,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              FilledButton.tonal(
                onPressed: state is ConnectionTestRunning ? null : _test,
                child: state is ConnectionTestRunning
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Test connection'),
              ),
              const SizedBox(width: 12),
              if (state is ConnectionTestDone)
                Expanded(child: _ResultChip(result: state.result)),
            ],
          ),
        ),
        if (state is ConnectionTestDone) _ResultDetail(result: state.result),
      ],
    );
  }

  Future<void> _selectModel(String model) async {
    setState(() => _modelController.text = model);
    await _persist();
  }
}

class _ResultChip extends StatelessWidget {
  const _ResultChip({required this.result});

  final ConnectionResult result;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final good = result.ok;
    return Row(
      // The summary is the error. Ellipsising it beside the button cut the useful half
      // off ("Server is running but h…"), so it wraps instead and the row grows.
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(good ? Icons.check_circle : Icons.error_outline,
            size: 18, color: good ? scheme.primary : scheme.error),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            result.summary,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}

/// The failure path is the reason this screen exists, so it gets the space: what the
/// provider said, and what to do about it.
class _ResultDetail extends StatelessWidget {
  const _ResultDetail({required this.result});

  final ConnectionResult result;

  /// Whether the panel body below has anything to draw. Kept in step with what that
  /// body actually renders — a lone model name is not shown there, so counting it here
  /// would leave an empty panel with nothing but the icon in it.
  bool get _hasExtra =>
      result.detail != null ||
      result.remedy != null ||
      result.models.length > 1;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // A success with nothing to add stays quiet. A failure always gets a panel, even one
    // carrying only its summary, so there is always somewhere to tap for the whole
    // message — and something to copy it from, rather than retyping it off the screen.
    if (result.ok && !_hasExtra) return const SizedBox.shrink();

    final onPanel = result.ok
        ? theme.colorScheme.onSurfaceVariant
        : theme.colorScheme.onErrorContainer;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Material(
        color: result.ok
            ? theme.colorScheme.surfaceContainerHighest
            : theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _showFullReport(context, result),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (result.remedy != null)
                        Text(result.remedy!, style: theme.textTheme.bodyMedium),
                      if (result.detail != null) ...[
                        if (result.remedy != null) const SizedBox(height: 8),
                        Text(
                          result.detail!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      if (result.models.length > 1) ...[
                        const SizedBox(height: 8),
                        Text('Models: ${result.models.take(8).join(', ')}',
                            style: theme.textTheme.bodySmall),
                      ],
                      if (!_hasExtra)
                        Text('Tap for the full message.',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: onPanel)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.info_outline, size: 18, color: onPanel),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Everything the provider reported, as one block. Shared by the dialog and the copy
/// button so what is read and what is pasted cannot drift apart.
String connectionReport(ConnectionResult result) => [
      result.summary,
      if (result.remedy != null) result.remedy!,
      if (result.detail != null) result.detail!,
      if (result.models.isNotEmpty) 'Models: ${result.models.join(', ')}',
    ].join('\n\n');

/// The whole message, selectable and copyable — a connection failure is the thing users
/// are most often asked to relay verbatim, and the panel truncates long ones.
Future<void> _showFullReport(
  BuildContext context,
  ConnectionResult result,
) async {
  final report = connectionReport(result);
  final messenger = ScaffoldMessenger.of(context);
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(result.ok ? 'Connection details' : 'Connection failed'),
      content: SingleChildScrollView(child: SelectableText(report)),
      actions: [
        TextButton(
          onPressed: () async {
            final navigator = Navigator.of(context);
            await Clipboard.setData(ClipboardData(text: report));
            navigator.pop();
            messenger.showSnackBar(
              const SnackBar(content: Text('Copied')),
            );
          },
          child: const Text('Copy'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

class _CloudModelPicker extends StatelessWidget {
  const _CloudModelPicker({
    required this.state,
    required this.selectedModel,
    required this.onChanged,
  });

  final ConnectionTestState state;
  final String selectedModel;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    if (state is! ConnectionTestDone) return const SizedBox.shrink();
    final models = (state as ConnectionTestDone).result.models;
    if (models.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: DropdownButtonFormField<String>(
        initialValue: models.contains(selectedModel) ? selectedModel : null,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Model',
          helperText: 'Models available to this API key.',
          border: OutlineInputBorder(),
        ),
        hint: const Text('Choose a model'),
        items: [
          for (final model in models)
            DropdownMenuItem<String>(value: model, child: Text(model)),
        ],
        onChanged: (model) {
          if (model != null) onChanged(model);
        },
      ),
    );
  }
}

/// Re-exported so the settings screen's imports stay short.
typedef MaskedKey = SecureKeyStore;
