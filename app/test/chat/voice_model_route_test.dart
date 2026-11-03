// Automatic mode and the on-device voice model: a ready model is used first
// (no detour through a phone service that fails on Chinese ROMs); without it
// the phone service runs, and its failures fall back to the model.

import 'package:dsh_app/state/voice_settings.dart';
import 'package:dsh_app/ui/chat/voice/voice_bridge.dart';
import 'package:dsh_app/ui/chat/voice/voice_controller.dart';
import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/composer_fakes.dart';
import 'voice_fallback_test.dart' show settleVoice;

void main() {
  late TextEditingController input;
  setUp(() => input = TextEditingController());
  tearDown(() => input.dispose());

  VoiceInputController controller(
    FakeVoiceBridge bridge,
    DshClient client, {
    VoiceMode mode = VoiceMode.auto,
    bool modelReady = false,
    String? requiredProviderId,
  }) {
    final voice = VoiceInputController(
      input: input,
      bridge: bridge,
      client: () => client,
      mode: () async => mode,
      modelReady: () => modelReady,
      requiredProviderId: requiredProviderId,
      observeLifecycle: false,
    );
    addTearDown(voice.dispose);
    return voice;
  }

  testWidgets('automatic mode records for a ready voice model even with a phone service', (tester) async {
    final client = DshClient.withCarrier(FakeRpcCarrier({'speech/catalog': (_) => readySpeechCatalog()}));
    final bridge = FakeVoiceBridge();
    final voice = controller(bridge, client, modelReady: true);
    await voice.start();
    await settleVoice(tester);
    expect(bridge.calls, isNot(contains('recognizer')));
    expect(bridge.calls.where((c) => c.startsWith('recorder:')), hasLength(1));
    expect(voice.engine, VoiceEngine.engine);
    await voice.cancel();
  });

  testWidgets('automatic mode uses the phone service while the model is not downloaded', (tester) async {
    final carrier = FakeRpcCarrier({'speech/catalog': (_) => readySpeechCatalog()});
    final bridge = FakeVoiceBridge();
    final voice = controller(bridge, DshClient.withCarrier(carrier));
    await voice.start();
    await settleVoice(tester);
    expect(bridge.calls, contains('recognizer'));
    expect(voice.engine, VoiceEngine.system);
    // The phone service is not held up by an engine probe.
    expect(carrier.calls, isEmpty);
    await voice.cancel();
  });

  testWidgets('a stale "ready" (the engine says otherwise) leaves the phone service in charge', (tester) async {
    final client = DshClient.withCarrier(
      FakeRpcCarrier({'speech/catalog': (_) => readySpeechCatalog(phase: 'unprepared')}),
    );
    final bridge = FakeVoiceBridge();
    final voice = controller(bridge, client, modelReady: true);
    await voice.start();
    await settleVoice(tester);
    expect(bridge.calls, contains('recognizer'));
    expect(bridge.calls.where((c) => c.startsWith('recorder:')), isEmpty);
    expect(voice.engine, VoiceEngine.system);
    await voice.cancel();
  });

  testWidgets('the service refusing with a permission error falls back (the app holds the permission)', (tester) async {
    var phase = 'unprepared';
    final client = DshClient.withCarrier(FakeRpcCarrier({'speech/catalog': (_) => readySpeechCatalog(phase: phase)}));
    final bridge = FakeVoiceBridge();
    final voice = controller(bridge, client);
    await voice.start();
    await settleVoice(tester);
    expect(voice.engine, VoiceEngine.system);
    // The model finished downloading meanwhile (or the service is Xiaomi's without its own permission).
    phase = 'standby';
    bridge.emit(const VoiceError(VoiceError.permission));
    bridge.emit(const VoiceEnd());
    await settleVoice(tester);
    expect(bridge.calls.where((c) => c.startsWith('recorder:')), hasLength(1));
    expect(voice.engine, VoiceEngine.engine);
    await voice.cancel();
  });

  testWidgets('nothing to fall back to offers 更换 (voice settings)', (tester) async {
    final client = DshClient.withCarrier(
      FakeRpcCarrier({'speech/catalog': (_) => readySpeechCatalog(phase: 'unprepared')}),
    );
    final bridge = FakeVoiceBridge();
    final voice = controller(bridge, client);
    final messages = <VoiceMessage>[];
    voice.onMessage = messages.add;
    await voice.start();
    await settleVoice(tester);
    bridge.emit(const VoiceError(5));
    await settleVoice(tester);
    expect(voice.phase, VoicePhase.idle);
    expect(messages.single.change, isTrue);
    expect(messages.single.text, contains('语音模型'));
  });

  testWidgets('voice model mode without a model says to download it', (tester) async {
    final client = DshClient.withCarrier(
      FakeRpcCarrier({'speech/catalog': (_) => readySpeechCatalog(phase: 'unprepared')}),
    );
    final bridge = FakeVoiceBridge();
    final voice = controller(bridge, client, mode: VoiceMode.engine);
    final messages = <VoiceMessage>[];
    voice.onMessage = messages.add;
    await voice.start();
    await settleVoice(tester);
    expect(bridge.calls, isNot(contains('recognizer')));
    expect(messages.single.change, isTrue);
    expect(messages.single.text, '请先下载语音模型并启动手机本地引擎');
  });
  testWidgets('pet fallback pins the offline provider despite a cloud default', (tester) async {
    final catalog = readySpeechCatalog();
    catalog['selection'] = {'providerId': 'cloud', 'language': 'auto'};
    (catalog['providers'] as List).add({'id': 'cloud', 'name': 'Cloud', 'location': 'cloud'});
    final carrier = FakeRpcCarrier({
      'speech/catalog': (_) => catalog,
      'speech/transcribe': (_) => {'text': 'recognized offline', 'audioSeconds': 1},
    });
    final bridge = FakeVoiceBridge()..recording = silentWav(1);
    input.text = 'existing draft ';
    input.selection = TextSelection.collapsed(offset: input.text.length);
    final voice = controller(
      bridge,
      DshClient.withCarrier(carrier),
      mode: VoiceMode.engine,
      requiredProviderId: 'sensevoice-local',
    );
    await voice.start();
    await settleVoice(tester);
    await voice.stop();
    await settleVoice(tester);
    expect((carrier.argsOf('speech/transcribe').single['request'] as Map)['providerId'], 'sensevoice-local');
    expect(input.text, contains('existing draft'));
    expect(input.text, contains('recognized offline'));
    expect(bridge.calls, isNot(contains('recognizer')));
  });

  testWidgets('pet fallback refuses a provider falsely labelled as cloud', (tester) async {
    final catalog = readySpeechCatalog();
    ((catalog['providers'] as List).single as Map)['location'] = 'cloud';
    final carrier = FakeRpcCarrier({'speech/catalog': (_) => catalog});
    final bridge = FakeVoiceBridge();
    final voice = controller(
      bridge,
      DshClient.withCarrier(carrier),
      mode: VoiceMode.engine,
      requiredProviderId: 'sensevoice-local',
    );
    await voice.start();
    await settleVoice(tester);
    expect(bridge.calls.where((c) => c.startsWith('recorder:')), isEmpty);
    expect(bridge.calls, isNot(contains('recognizer')));
    expect(voice.phase, VoicePhase.idle);
  });

  testWidgets('remote chat uses the phone model and never uploads audio to the remote host', (tester) async {
    final remote = FakeRpcCarrier({});
    final local = FakeRpcCarrier({
      'speech/catalog': (_) => readySpeechCatalog(),
      'speech/transcribe': (_) => {'text': 'local recognition', 'audioSeconds': 1},
    });
    final remoteClient = DshClient.withCarrier(remote);
    final localClient = DshClient.withCarrier(local);
    final bridge = FakeVoiceBridge()..recording = silentWav(1);
    final voice = VoiceInputController(
      input: input,
      bridge: bridge,
      client: () => remoteClient,
      speechClient: () => localClient,
      mode: () async => VoiceMode.engine,
      requiredProviderId: 'sensevoice-local',
      observeLifecycle: false,
    );
    addTearDown(voice.dispose);
    await voice.start();
    await settleVoice(tester);
    await voice.stop();
    await settleVoice(tester);
    expect(input.text, contains('local recognition'));
    expect(local.argsOf('speech/transcribe'), hasLength(1));
    expect(remote.calls, isEmpty);
  });

  testWidgets('remote chat cannot use remote speech when the phone engine is absent', (tester) async {
    final remote = FakeRpcCarrier({'speech/catalog': (_) => readySpeechCatalog()});
    final remoteClient = DshClient.withCarrier(remote);
    final bridge = FakeVoiceBridge();
    final voice = VoiceInputController(
      input: input,
      bridge: bridge,
      client: () => remoteClient,
      speechClient: () => null,
      mode: () async => VoiceMode.engine,
      requiredProviderId: 'sensevoice-local',
      observeLifecycle: false,
    );
    addTearDown(voice.dispose);
    await voice.start();
    await settleVoice(tester);
    expect(voice.phase, VoicePhase.idle);
    expect(remote.calls, isEmpty);
    expect(bridge.calls.where((c) => c.startsWith('recorder:')), isEmpty);
  });

  testWidgets('switching the remote chat host cancels a phone-model recording', (tester) async {
    final local = FakeRpcCarrier({'speech/catalog': (_) => readySpeechCatalog()});
    final localClient = DshClient.withCarrier(local);
    var remote = DshClient.withCarrier(FakeRpcCarrier({}));
    final bridge = FakeVoiceBridge()..recording = silentWav(1);
    final voice = VoiceInputController(
      input: input,
      bridge: bridge,
      client: () => remote,
      speechClient: () => localClient,
      mode: () async => VoiceMode.engine,
      requiredProviderId: 'sensevoice-local',
      observeLifecycle: false,
    );
    addTearDown(voice.dispose);
    await voice.start();
    await settleVoice(tester);
    expect(voice.phase, VoicePhase.listening);
    remote = DshClient.withCarrier(FakeRpcCarrier({}));
    voice.ensureFresh();
    await settleVoice(tester);
    expect(voice.phase, VoicePhase.idle);
    expect(local.argsOf('speech/transcribe'), isEmpty);
    expect(input.text, isEmpty);
  });

  testWidgets('losing the phone engine cancels recording while the remote host stays connected', (tester) async {
    final local = FakeRpcCarrier({'speech/catalog': (_) => readySpeechCatalog()});
    DshClient? localClient = DshClient.withCarrier(local);
    final remote = DshClient.withCarrier(FakeRpcCarrier({}));
    final bridge = FakeVoiceBridge()..recording = silentWav(1);
    final voice = VoiceInputController(
      input: input,
      bridge: bridge,
      client: () => remote,
      speechClient: () => localClient,
      mode: () async => VoiceMode.engine,
      requiredProviderId: 'sensevoice-local',
      observeLifecycle: false,
    );
    addTearDown(voice.dispose);
    await voice.start();
    await settleVoice(tester);
    expect(voice.phase, VoicePhase.listening);
    localClient = null;
    voice.ensureFresh();
    await settleVoice(tester);
    expect(voice.phase, VoicePhase.idle);
    expect(local.argsOf('speech/transcribe'), isEmpty);
  });

  testWidgets('a model that becomes unavailable clears the cached capability', (tester) async {
    var phase = 'standby';
    final local = FakeRpcCarrier({'speech/catalog': (_) => readySpeechCatalog(phase: phase)});
    final client = DshClient.withCarrier(local);
    final bridge = FakeVoiceBridge(caps: const VoiceCapabilities(recognizer: false, recorder: true));
    final voice = VoiceInputController(
      input: input,
      bridge: bridge,
      client: () => client,
      speechClient: () => client,
      requiredProviderId: 'sensevoice-local',
      observeLifecycle: false,
    );
    addTearDown(voice.dispose);
    await voice.refresh();
    expect(voice.engineReady, isTrue);
    phase = 'unprepared';
    await voice.refresh();
    expect(voice.engineReady, isFalse);
    expect(voice.available, isFalse);
  });

  testWidgets('provider policy follows host changes while preserving local selection', (tester) async {
    final catalog = readySpeechCatalog();
    (catalog['providers'] as List).add({
      'id': 'other-local',
      'name': 'Other',
      'location': 'host-local',
      'languages': ['auto'],
      'preparation': {'phase': 'standby'},
    });
    catalog['selection'] = {'providerId': 'other-local', 'language': 'auto'};
    final local = FakeRpcCarrier({
      'speech/catalog': (_) => catalog,
      'speech/transcribe': (_) => {'text': 'recognized', 'audioSeconds': 1},
    });
    final localClient = DshClient.withCarrier(local);
    final remote = FakeRpcCarrier({});
    final remoteClient = DshClient.withCarrier(remote);
    var active = localClient;
    var remoteHost = false;
    final bridge = FakeVoiceBridge()..recording = silentWav(1);
    final voice = VoiceInputController(
      input: input,
      bridge: bridge,
      client: () => active,
      speechClient: () => localClient,
      requiredProviderIdForRun: () => remoteHost ? 'sensevoice-local' : null,
      mode: () async => VoiceMode.engine,
      observeLifecycle: false,
    );
    addTearDown(voice.dispose);
    await voice.start();
    await settleVoice(tester);
    await voice.stop();
    await settleVoice(tester);
    expect((local.argsOf('speech/transcribe').last['request'] as Map)['providerId'], 'other-local');
    remoteHost = true;
    active = remoteClient;
    voice.ensureFresh();
    await settleVoice(tester);
    await voice.start();
    await settleVoice(tester);
    await voice.stop();
    await settleVoice(tester);
    expect((local.argsOf('speech/transcribe').last['request'] as Map)['providerId'], 'sensevoice-local');
    expect(remote.calls, isEmpty);
  });
}
