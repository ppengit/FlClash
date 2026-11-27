import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/pages/editor.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/profiles/edit.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/gestures.dart' show kSecondaryButton, PointerDeviceKind;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
// ignore: depend_on_referenced_packages
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import '../helpers/app_paths.dart';
import '../helpers/host_scaffold.dart';
import '../helpers/test_app.dart';
import '../plugins/code_forge/support.dart' show initEditorNative;

class _NoopSetupAction extends SetupAction {
  @override
  void autoApplyProfile() {}
}

class _MockCore extends Mock implements CoreHandlerInterface {}

base class _TestPlatformFile extends PlatformFile {
  _TestPlatformFile(this.bytes);

  final Uint8List bytes;

  @override
  String get name => 'profile.yaml';

  @override
  Uri get uri => Uri.file(name);

  @override
  XFile get xFile => XFile.fromData(bytes, name: name);

  @override
  int? lengthSync() => bytes.length;

  @override
  Future<int?> length() async => bytes.length;

  @override
  Future<Uint8List> readAsBytes() async => bytes;

  @override
  Stream<Uint8List> readAsByteStream() => Stream.value(bytes);
}

class _TestFilePickerPlatform extends FilePickerPlatform
    with MockPlatformInterfaceMixin {
  _TestFilePickerPlatform(this.bytes);

  final Uint8List bytes;

  @override
  Future<PlatformFile?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus status)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    return _TestPlatformFile(bytes);
  }
}

Profile _fileProfile() => Profile.normal(label: 'test');

Uint8List _bytes(String text) => Uint8List.fromList(utf8.encode(text));

Future<void> _writeProfile(Profile profile, String text) async {
  final file = await profile.file;
  await file.writeAsString(text);
}

Future<void> _pumpEditProfile(
  WidgetTester tester, {
  required Profile profile,
  List<Override> overrides = const [],
}) async {
  const size = Size(900, 800);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final container = ProviderContainer(
    overrides: [
      setupActionProvider.overrideWith(() => _NoopSetupAction()),
      ...overrides,
    ],
  );
  addTearDown(container.dispose);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
  });
  globalState.container = container;
  container.read(viewSizeProvider.notifier).value = size;

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: HostApp(
        navigatorKey: globalState.navigatorKey,
        builder: (context, child) => wrapAppScopes(context, child!),
        home: HostScaffold(
          body: Navigator(
            pages: [
              const RootPage(child: SizedBox.shrink()),
              RootPage(child: EditProfileView(profile: profile)),
            ],
            onDidRemovePage: (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

Finder _fileRow() =>
    find.widgetWithText(DecorationListItem, currentAppLocalizations.profile);

Future<void> _waitForFileRow(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    if (_fileRow().evaluate().isNotEmpty) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(_fileRow(), findsOneWidget);
}

Future<String> _waitForEditorText(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    final editor = find.byType(EditorView);
    if (editor.evaluate().isNotEmpty) {
      final text = tester.state<EditorViewState>(editor).controller?.text;
      if (text != null) return text;
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  fail('editor content did not load');
}

Future<void> _waitForEditorToClose(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    if (find.byType(EditorPage).evaluate().isEmpty) return;
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(find.byType(EditorPage), findsNothing);
}

Future<EditorPage> _openEditor(WidgetTester tester) async {
  await tester.tap(_fileRow());
  await tester.pump();
  await _waitForEditorText(tester);
  return tester.widget<EditorPage>(find.byType(EditorPage));
}

Future<void> _uploadProfile(WidgetTester tester, Uint8List bytes) async {
  final previous = FilePickerPlatform.instance;
  FilePickerPlatform.instance = _TestFilePickerPlatform(bytes);
  addTearDown(() => FilePickerPlatform.instance = previous);

  await tester.tap(
    _fileRow(),
    buttons: kSecondaryButton,
    kind: PointerDeviceKind.mouse,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(currentAppLocalizations.upload));
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
  for (var i = 0; i < 20; i++) {
    if (find.text(bytes.length.traffic.show).evaluate().isNotEmpty) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(find.text(bytes.length.traffic.show), findsOneWidget);
}

Future<void> _saveEditorContent(
  WidgetTester tester,
  EditorPage editor,
  String text,
) async {
  final context = tester.element(find.byType(EditorPage));
  await tester.runAsync(() async {
    await editor.onSave!(context, editor.title, EditorContent.text(text));
  });
  await tester.pump();
}

Future<void> _waitForAlert(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    if (find.byType(AlertDialog).evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(find.byType(AlertDialog), findsOneWidget);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('edit_profile_test_');
    await useAppPaths(tempDir);
    await initEditorNative();
  });

  tearDownAll(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  testWidgets('editing after upload opens the uploaded bytes', (tester) async {
    final profile = _fileProfile();
    await tester.runAsync(() => _writeProfile(profile, 'mode: rule\n'));
    await _pumpEditProfile(tester, profile: profile);
    await _waitForFileRow(tester);

    final uploaded = _bytes('mode: direct\n');
    await _uploadProfile(tester, uploaded);
    await _openEditor(tester);

    expect(await _waitForEditorText(tester), utf8.decode(uploaded));
  });

  testWidgets('upload takes precedence over an earlier cached edit', (
    tester,
  ) async {
    final profile = _fileProfile();
    await tester.runAsync(() => _writeProfile(profile, 'mode: rule\n'));
    final core = _MockCore();
    when(() => core.validateConfig(any())).thenAnswer((_) async => null);
    await _pumpEditProfile(
      tester,
      profile: profile,
      overrides: [
        coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
      ],
    );
    await _waitForFileRow(tester);

    final editor = await _openEditor(tester);
    await _saveEditorContent(tester, editor, 'mode: cached\n');
    await _waitForEditorToClose(tester);

    final uploaded = _bytes('mode: direct\n');
    await _uploadProfile(tester, uploaded);
    await _openEditor(tester);

    expect(await _waitForEditorText(tester), utf8.decode(uploaded));
  });

  testWidgets('validation exception keeps the editor open without bytes', (
    tester,
  ) async {
    final profile = _fileProfile();
    await tester.runAsync(() => _writeProfile(profile, 'mode: rule\n'));
    final core = _MockCore();
    when(
      () => core.validateConfig(any()),
    ).thenThrow(const MessageException('validation failed'));
    await _pumpEditProfile(
      tester,
      profile: profile,
      overrides: [
        coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
      ],
    );
    await _waitForFileRow(tester);

    final editor = await _openEditor(tester);
    await _saveEditorContent(tester, editor, 'mode: broken\n');
    await _waitForAlert(tester);

    expect(find.byType(EditorPage), findsOneWidget);
    expect(find.text('validation failed'), findsOneWidget);

    Navigator.of(tester.element(find.byType(AlertDialog))).pop();
    await tester.pump();
    Navigator.of(tester.element(find.byType(EditorPage))).pop();
    await _waitForEditorToClose(tester);
    await _openEditor(tester);

    expect(await _waitForEditorText(tester), 'mode: rule\n');
  });

  testWidgets('valid editor content still returns to the profile page', (
    tester,
  ) async {
    final profile = _fileProfile();
    await tester.runAsync(() => _writeProfile(profile, 'mode: rule\n'));
    final core = _MockCore();
    when(() => core.validateConfig(any())).thenAnswer((_) async => null);
    await _pumpEditProfile(
      tester,
      profile: profile,
      overrides: [
        coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
      ],
    );
    await _waitForFileRow(tester);

    final editor = await _openEditor(tester);
    await _saveEditorContent(tester, editor, 'mode: direct\n');
    await _waitForEditorToClose(tester);

    expect(find.byType(EditorPage), findsNothing);
    await _openEditor(tester);
    expect(await _waitForEditorText(tester), 'mode: direct\n');
  });

  testWidgets('invalid editor content still shows its validation message', (
    tester,
  ) async {
    final profile = _fileProfile();
    await tester.runAsync(() => _writeProfile(profile, 'mode: rule\n'));
    final core = _MockCore();
    when(
      () => core.validateConfig(any()),
    ).thenAnswer((_) async => 'invalid config');
    await _pumpEditProfile(
      tester,
      profile: profile,
      overrides: [
        coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
      ],
    );
    await _waitForFileRow(tester);

    final editor = await _openEditor(tester);
    await _saveEditorContent(tester, editor, 'mode: invalid\n');
    await _waitForAlert(tester);

    expect(find.byType(EditorPage), findsOneWidget);
    expect(find.text('invalid config'), findsOneWidget);
  });
}
