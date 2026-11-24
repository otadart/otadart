/// Developer interface for OTADart application updates.
///
/// On Android, iOS and desktop it receives signed patches for builds made with
/// `otadart release`. On the web it detects newly deployed builds and reloads
/// onto them. Experimental preview.
library;

export 'src/client.dart' if (dart.library.js_interop) 'src/client_web.dart';
export 'src/models.dart';
