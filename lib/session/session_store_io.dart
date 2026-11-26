import 'dart:io';
import 'package:flutter/services.dart';
import 'session_store.dart';

SessionStore createSessionStore() => MobileSessionStore();

/// Mobile storage. The resolver may be supplied by a host-side test.
class MobileSessionStore
    implements SessionStore, SessionArchive, GuardedSessionStore {
  MobileSessionStore({Future<Directory> Function()? directoryResolver})
    : _directoryResolver = directoryResolver ?? _platformDirectory;

  static const _channel = MethodChannel('com.humanifest.phonopticon/export');
  final Future<Directory> Function() _directoryResolver;

  static Future<Directory> _platformDirectory() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      throw UnsupportedError(
        'Durable local session storage is not configured for this platform.',
      );
    }
    final path = await _channel.invokeMethod<String>('sessionDirectory');
    if (path == null || path.isEmpty) {
      throw StateError('Local session storage is unavailable.');
    }
    return Directory(path);
  }

  @override
  Future<String?> loadLatest() async {
    final directory = await _directoryResolver();
    if (!await directory.exists()) return null;
    final pointer = File('${directory.path}/.latest');
    final pointerType = await FileSystemEntity.type(
      pointer.path,
      followLinks: false,
    );
    if (pointerType != FileSystemEntityType.notFound) {
      if (pointerType != FileSystemEntityType.file) {
        throw const FormatException('Invalid latest session pointer.');
      }
      final name = await pointer.readAsString();
      if (!isValidSessionId(name)) {
        throw const FormatException('Invalid latest session pointer.');
      }
      final snapshot = File('${directory.path}/$name.json');
      if (await FileSystemEntity.type(snapshot.path, followLinks: false) !=
          FileSystemEntityType.file) {
        throw const FormatException('Latest session snapshot is missing.');
      }
      return snapshot.readAsString();
    }
    // Preserve compatibility with snapshots written before the pointer existed.
    final files = await directory
        .list(followLinks: false)
        .where((entry) {
          if (entry is! File) return false;
          final name = entry.uri.pathSegments.last;
          return name.endsWith('.json') &&
              isValidSessionId(name.substring(0, name.length - '.json'.length));
        })
        .cast<File>()
        .toList();
    if (files.isEmpty) return null;
    final dated = await Future.wait(
      files.map((file) async => (file, await file.lastModified())),
    );
    dated.sort((a, b) {
      final time = b.$2.compareTo(a.$2);
      return time != 0 ? time : a.$1.path.compareTo(b.$1.path);
    });
    return dated.first.$1.readAsString();
  }

  @override
  Future<List<String>> listSessionIds() async {
    final directory = await _directoryResolver();
    if (!await directory.exists()) return [];
    final ids = <String>[];
    await for (final entry in directory.list(followLinks: false)) {
      if (entry is! File) continue;
      final name = entry.uri.pathSegments.last;
      if (!name.endsWith('.json')) continue;
      final id = name.substring(0, name.length - '.json'.length);
      if (isValidSessionId(id)) ids.add(id);
    }
    ids.sort();
    return ids;
  }

  @override
  Future<String?> loadById(String sessionId) async {
    validateSessionId(sessionId);
    final directory = await _directoryResolver();
    final file = File('${directory.path}/$sessionId.json');
    final type = await FileSystemEntity.type(file.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return null;
    if (type != FileSystemEntityType.file) {
      throw const FormatException('Invalid session snapshot.');
    }
    return file.readAsString();
  }

  @override
  Future<void> save(String sessionId, String snapshot) async {
    validateSessionId(sessionId);
    await _withSessionLock(
      sessionId,
      (directory) => _replace(directory, sessionId, snapshot),
    );
  }

  @override
  Future<void> saveIfUnchanged(
    String sessionId,
    String snapshot, {
    required String? expectedSnapshot,
  }) async {
    validateSessionId(sessionId);
    await _withSessionLock(sessionId, (directory) async {
      final file = File('${directory.path}/$sessionId.json');
      final type = await FileSystemEntity.type(file.path, followLinks: false);
      if (type != FileSystemEntityType.notFound &&
          type != FileSystemEntityType.file) {
        throw const FormatException('Invalid session snapshot.');
      }
      final current = type == FileSystemEntityType.file
          ? await file.readAsString()
          : null;
      // Creation must not adopt another writer's identical record. For an
      // update, the snapshot can be committed even if the later pointer
      // update fails; retrying that identical update is safe.
      if (expectedSnapshot == null
          ? current != null
          : current != expectedSnapshot && current != snapshot) {
        throw const SessionWriteConflict(
          'This session changed elsewhere. Export your current work or save it as a new session.',
        );
      }
      await _replace(directory, sessionId, snapshot);
    });
  }

  /// The marker protects cooperating instances, including same-process isolates.
  /// After a crash a stale marker may remain; callers can save a new session.
  Future<void> _withSessionLock(
    String sessionId,
    Future<void> Function(Directory) action,
  ) async {
    final directory = await _directoryResolver();
    await directory.create(recursive: true);
    final marker = File('${directory.path}/.$sessionId.write-lock');
    try {
      await marker.create(exclusive: true);
    } on FileSystemException catch (error) {
      final type = await FileSystemEntity.type(marker.path, followLinks: false);
      // The other writer may release its marker between our failed exclusive
      // create and this stat. Preserve the conflict classification in that
      // race; POSIX EEXIST is 17 and Windows ERROR_ALREADY_EXISTS is 183.
      if (type != FileSystemEntityType.notFound ||
          error.osError?.errorCode == 17 ||
          error.osError?.errorCode == 183) {
        throw const SessionWriteConflict(
          'This session is busy or has a stale save lock. Export your work or save it as a new session.',
        );
      }
      rethrow;
    }
    try {
      await action(directory);
    } finally {
      // This marker was created by this call. Never clear a pre-existing lock.
      // If cleanup fails, preserve the lock and surface the uncertain state.
      await marker.delete();
    }
  }

  Future<void> _replace(
    Directory directory,
    String sessionId,
    String snapshot,
  ) async {
    // A temporary directory gives each save unique staging paths on the same
    // filesystem, so replacing each file is atomic. Keep other sessions intact.
    final staging = await directory.createTemp('.saving-');
    final temporarySnapshot = File('${staging.path}/snapshot.tmp');
    await temporarySnapshot.writeAsString(snapshot, flush: true);
    await temporarySnapshot.rename('${directory.path}/$sessionId.json');
    final temporaryPointer = File('${staging.path}/latest.tmp');
    await temporaryPointer.writeAsString(sessionId, flush: true);
    await temporaryPointer.rename('${directory.path}/.latest');
    // Cleanup is best effort: a failure here must not report a committed save
    // as failed. Failed writes may leave staging files for later inspection.
    try {
      await staging.delete();
    } on FileSystemException {
      // The session and pointer have already been committed.
    }
  }
}
