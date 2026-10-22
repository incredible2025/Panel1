import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

HttpClientProvider? _previousProvider;
bool _installed = false;

/// Replaces NetworkImage transport with a local image for optional visual QA.
///
/// Call from per-test setup and pair with [restoreQaArtwork] in teardown.
/// No socket-backed HttpClient is created, including for unknown image URLs.
Future<void> installQaArtwork() async {
  if (!const bool.fromEnvironment('CAPTURE_UI_ART') || _installed) return;
  final path = Platform.environment['STREAMLINE_QA_ART'];
  if (path == null || path.trim().isEmpty) {
    throw StateError(
      'CAPTURE_UI_ART requires STREAMLINE_QA_ART to name a local image.',
    );
  }
  final bytes = await File(path).readAsBytes();
  if (bytes.isEmpty) throw StateError('The local QA artwork image is empty.');

  _previousProvider = debugNetworkImageHttpClientProvider;
  debugNetworkImageHttpClientProvider = () => _QaHttpClient(bytes);
  _installed = true;
  PaintingBinding.instance.imageCache.clear();
  PaintingBinding.instance.imageCache.clearLiveImages();
}

void restoreQaArtwork() {
  if (!_installed) return;
  debugNetworkImageHttpClientProvider = _previousProvider;
  _previousProvider = null;
  _installed = false;
  PaintingBinding.instance.imageCache.clear();
  PaintingBinding.instance.imageCache.clearLiveImages();
}

class _QaHttpClient extends Fake implements HttpClient {
  _QaHttpClient(this.bytes);

  final Uint8List bytes;

  @override
  bool autoUncompress = false;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _QaRequest(bytes);

  @override
  void close({bool force = false}) {}
}

class _QaRequest extends Fake implements HttpClientRequest {
  _QaRequest(this.bytes);

  final Uint8List bytes;

  @override
  final HttpHeaders headers = _QaHeaders();

  @override
  Future<HttpClientResponse> close() async => _QaResponse(bytes);
}

class _QaHeaders extends Fake implements HttpHeaders {
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}
}

class _QaResponse extends Fake implements HttpClientResponse {
  _QaResponse(this.bytes);

  final Uint8List bytes;

  @override
  int get statusCode => HttpStatus.ok;

  @override
  int get contentLength => bytes.length;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(bytes).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  Future<E> drain<E>([E? futureValue]) =>
      Stream<List<int>>.value(bytes).drain<E>(futureValue);
}
