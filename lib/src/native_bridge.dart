import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'package:ffi/ffi.dart';
import 'models.dart';

typedef _OpenNative =
    Pointer<Void> Function(Pointer<Utf8>, Pointer<Pointer<Utf8>>);
typedef _Open = Pointer<Void> Function(Pointer<Utf8>, Pointer<Pointer<Utf8>>);
typedef _CallNative = Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>);
typedef _Call = Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>);
typedef _GlobalCallNative = Pointer<Utf8> Function(Pointer<Utf8>);
typedef _GlobalCall = Pointer<Utf8> Function(Pointer<Utf8>);
typedef _FreeNative = Void Function(Pointer<Utf8>);
typedef _Free = void Function(Pointer<Utf8>);
typedef _CloseNative = Void Function(Pointer<Void>);
typedef _Close = void Function(Pointer<Void>);

class NativeBridge {
  final Isolate _isolate;
  final SendPort _worker;
  final ReceivePort _responses;
  final Map<int, Completer<Map<String, Object?>>> _pending = {};
  int _nextId = 0;
  bool _closed = false;
  NativeBridge._(this._isolate, this._worker, this._responses) {
    _responses.listen((dynamic value) {
      final response = value as Map;
      final request = _pending.remove(response['id']);
      if (request == null) return;
      if (response['error'] != null) {
        request.completeError(OtaDartException(response['error'] as String));
      } else {
        request.complete(Map<String, Object?>.from(response['value'] as Map));
      }
    });
  }
  static Future<NativeBridge> open({
    String? libraryPath,
    Map<String, Object?>? config,
  }) async {
    final ready = ReceivePort();
    final responses = ReceivePort();
    final isolate = await Isolate.spawn(_workerMain, <Object?>[
      ready.sendPort,
      responses.sendPort,
      libraryPath,
      config,
    ]);
    try {
      final result = Map<String, Object?>.from(await ready.first as Map);
      if (result['error'] != null) {
        throw OtaDartException(result['error'] as String);
      }
      return NativeBridge._(isolate, result['port'] as SendPort, responses);
    } catch (_) {
      isolate.kill(priority: Isolate.immediate);
      responses.close();
      rethrow;
    } finally {
      ready.close();
    }
  }

  Future<Map<String, Object?>> call(Map<String, Object?> request) {
    if (_closed) {
      return Future.error(const OtaDartException('Client is closed'));
    }
    return _enqueue(request);
  }

  Future<Map<String, Object?>> _enqueue(Map<String, Object?> request) {
    final id = ++_nextId;
    final completer = Completer<Map<String, Object?>>();
    _pending[id] = completer;
    _worker.send({'id': id, 'request': request});
    return completer.future;
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _enqueue({'operation': 'dispose'});
    _responses.close();
    _isolate.kill(priority: Isolate.immediate);
    for (final pending in _pending.values) {
      pending.completeError(const OtaDartException('Client closed'));
    }
    _pending.clear();
  }
}

void _workerMain(List<Object?> args) {
  final ready = args[0] as SendPort;
  final responses = args[1] as SendPort;
  final path = args[2] as String?;
  final config = args[3] as Map<String, Object?>?;
  Pointer<Void> handle = nullptr;
  try {
    // On Android the OTADart engine is libflutter.so, loaded privately by the
    // app, so it has to be opened by name. Elsewhere it is in the process.
    final library = path != null
        ? DynamicLibrary.open(path)
        : Platform.isAndroid
        ? DynamicLibrary.open('libflutter.so')
        : DynamicLibrary.process();
    final free = library.lookupFunction<_FreeNative, _Free>(
      'otadart_string_free',
    );
    _Call? call;
    _GlobalCall? globalCall;
    _Close? close;
    if (config != null) {
      final open = library.lookupFunction<_OpenNative, _Open>('otadart_open');
      call = library.lookupFunction<_CallNative, _Call>('otadart_call');
      close = library.lookupFunction<_CloseNative, _Close>('otadart_close');
      final input = jsonEncode(config).toNativeUtf8();
      final error = calloc<Pointer<Utf8>>();
      try {
        handle = open(input, error);
        if (handle == nullptr) {
          final message = error.value == nullptr
              ? 'Native runtime could not open'
              : error.value.toDartString();
          if (error.value != nullptr) free(error.value);
          throw OtaDartException(message);
        }
      } finally {
        calloc.free(input);
        calloc.free(error);
      }
    } else {
      globalCall = library.lookupFunction<_GlobalCallNative, _GlobalCall>(
        'otadart_engine_call',
      );
    }
    final port = ReceivePort();
    ready.send({'port': port.sendPort});
    port.listen((dynamic incoming) {
      final message = incoming as Map;
      final id = message['id'];
      try {
        final request = Map<String, Object?>.from(message['request'] as Map);
        if (request['operation'] == 'dispose') {
          if (handle != nullptr) close!(handle);
          handle = nullptr;
          responses.send({'id': id, 'value': <String, Object?>{}});
          port.close();
          return;
        }
        final input = jsonEncode(request).toNativeUtf8();
        Pointer<Utf8> output = nullptr;
        try {
          output = call != null ? call(handle, input) : globalCall!(input);
          if (output == nullptr) {
            throw const OtaDartException('Native runtime returned no response');
          }
          final decoded = jsonDecode(output.toDartString()) as Map;
          if (decoded['ok'] != true) {
            throw OtaDartException(decoded['error'].toString());
          }
          responses.send({'id': id, 'value': decoded['value']});
        } finally {
          calloc.free(input);
          if (output != nullptr) free(output);
        }
      } catch (error) {
        responses.send({'id': id, 'error': error.toString()});
      }
    });
  } catch (error) {
    ready.send({
      'error':
          'OTADart native runtime unavailable: $error. A stock Flutter engine does not include OTADart.',
    });
  }
}
