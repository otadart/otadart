# otadart example

A Flutter screen that shows the running version and patch, checks for an
update, and downloads it.

```dart
import 'package:flutter/material.dart';
import 'package:otadart/otadart.dart';

const appId = 'YOUR-APP-ID'; // from otadart.yaml

class UpdateCard extends StatefulWidget {
  const UpdateCard({super.key});
  @override
  State<UpdateCard> createState() => _UpdateCardState();
}

class _UpdateCardState extends State<UpdateCard> {
  OtaDart? updates;
  OtaDartInfo? info;
  String message = '';

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    // Null in `flutter run` and builds not made with `otadart release`.
    updates = await OtaDart.tryInitialize(appId: appId);
    if (updates == null) {
      setState(() => message = 'Updates are off in this build');
      return;
    }
    await updates!.markCurrentBootHealthy(); // the app started fine
    info = await updates!.info();
    setState(() {});
  }

  Future<void> _check() async {
    final offer = await updates!.availableUpdate();
    if (!offer.hasUpdate) {
      setState(() => message = offer.availability ==
              UpdateAvailability.readyOnNextLaunch
          ? 'Restart the app to finish updating'
          : 'You are up to date');
      return;
    }
    setState(() => message = 'Downloading patch #${offer.patchNumber}…');
    final result = await updates!.update();
    setState(() => message = result.readyOnNextLaunch
        ? 'Patch #${result.patchNumber} is ready — restart the app'
        : 'You are up to date');
  }

  @override
  void dispose() {
    updates?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(children: [
        Text(info?.label ?? 'Loading…'),          // 1.2.0+5 · patch #3
        if (info?.nextPatch != null)
          Text('Patch #${info!.nextPatch!.number} applies on next launch'),
        Text(message),
        if (updates != null)
          TextButton(onPressed: _check, child: const Text('Check for updates')),
      ]),
    );
  }
}
```
