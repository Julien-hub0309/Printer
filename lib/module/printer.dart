import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:async';

class Printer {
  final String ipAddress;
  final int port;
  final String name;
  final String model;
  final String manufacturer;
  String status;

  Printer({
    required this.ipAddress,
    required this.port,
    required this.name,
    required this.model,
    required this.manufacturer,
    required this.status,
  });
}

class NetworkPrinterScanner {
  List<Printer> discoveredPrinters = [];
  bool isScanning = false;

  /// Retourne la liste des noms des imprimantes découvertes lors du scan réseau courant
  List<String> getDiscoveredPrinterNames() {
    return discoveredPrinters.map((printer) => printer.name).toList();
  }

  /// Récupère la liste des noms des imprimantes déjà configurées sur le système Linux
  Future<List<String>> getSystemPrinterNames() async {
    if (!Platform.isLinux) return [];

    try {
      final ProcessResult result = await Process.run('lpstat', ['-a']);

      if (result.exitCode != 0 || result.stdout.toString().isEmpty) {
        return [];
      }

      final List<String> printerNames = [];
      final lines = result.stdout.toString().split('\n');

      for (var line in lines) {
        if (line.trim().isEmpty) continue;
        final firstWord = line.split(' ').first;
        printerNames.add(firstWord);
      }

      return printerNames;
    } catch (_) {
      return [];
    }
  }

  /// Déclenche un scan réseau réel par balayage de sockets TCP
  Future<void> scanNetwork({
    Function(String msg, String type)? onLog,
    void Function()? onPrinterDiscovered,
  }) async {
    if (isScanning) return;

    isScanning = true;
    discoveredPrinters.clear();
    onLog?.call('Recherche des interfaces réseau actives...', 'info');

    final networkInterfaces =
        await NetworkInterface.list(includeLoopback: false);
    if (networkInterfaces.isEmpty) {
      onLog?.call('Erreur : Aucune interface réseau détectée.', 'error');
      isScanning = false;
      return;
    }

    final primaryInterface = networkInterfaces.first;
    final addresses = primaryInterface.addresses;
    if (addresses.isEmpty) {
      onLog?.call('Erreur : Pas d\'adresse IP locale valide.', 'error');
      isScanning = false;
      return;
    }

    final ipStr = addresses.first.address;
    if (!ipStr.contains('.')) {
      onLog?.call('Réseau IPv6 ignoré pour le scan de proximité.', 'info');
      isScanning = false;
      return;
    }

    final segments = ipStr.split('.');
    final subnet = '${segments[0]}.${segments[1]}.${segments[2]}';
    onLog?.call(
        'Scan réel en cours sur la plage réseau : $subnet.1 à $subnet.254',
        'info');

    final List<Future<void>> scanTasks = [];
    final List<int> printerPorts = [631, 9100];

    for (int i = 1; i <= 254; i++) {
      final host = '$subnet.$i';
      for (int port in printerPorts) {
        scanTasks
            .add(_probeSocket(host, port, onLog, onPrinterDiscovered));
      }
    }

    await Future.wait(scanTasks);
    isScanning = false;
    onLog?.call('Scan réseau terminé. Équipements prêts.', 'sys');
  }

  /// Sonde un hôte spécifique, l'écoute activement et extrait son identité
  Future<void> _probeSocket(
    String host,
    int port,
    Function(String msg, String type)? onLog,
    void Function()? onPrinterDiscovered,
  ) async {
    Socket? socket;
    try {
      socket = await Socket.connect(host, port,
          timeout: const Duration(seconds: 1));

      String manufacturer = 'Generic';
      String model =
          (port == 631) ? 'IPP Everywhere Printer' : 'Raw Network Printer';
      String displayName = 'Imprimante Réseau @ $host';

      final List<int> buffer = [];
      final completer = Completer<void>();

      final subscription = socket.listen(
        (List<int> data) {
          buffer.addAll(data);
        },
        onError: (error) {
          if (!completer.isCompleted) completer.complete();
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete();
        },
        cancelOnError: true,
      );

      if (port == 631) {
        // Construction de l'URI requis par le protocole IPP
        final String targetUri = 'ipp://$host:631/ipp/print';
        final List<int> uriBytes = utf8.encode(targetUri);
        final int uriLength = uriBytes.length;

        // FIX: construction explicite des bytes IPP sans spread inline ambigu
        final List<int> charsetName = utf8.encode('attributes-charset');
        final List<int> charsetVal = utf8.encode('utf-8');
        final List<int> langName = utf8.encode('attributes-natural-language');
        final List<int> langVal = utf8.encode('en');
        final List<int> printerUriName = utf8.encode('printer-uri');

        final List<int> ippHeader = [
          0x02, 0x00, // Version IPP 2.0
          0x00, 0x0b, // Operation-ID: Get-Printer-Attributes
          0x00, 0x00, 0x00, 0x01, // Request-ID: 1
          0x01, // Operation Attributes Tag
          // attributes-charset: utf-8
          0x47,
          0x00, charsetName.length,
          ...charsetName,
          0x00, charsetVal.length,
          ...charsetVal,
          // attributes-natural-language: en
          0x48,
          0x00, langName.length,
          ...langName,
          0x00, langVal.length,
          ...langVal,
          // printer-uri
          0x45,
          0x00, printerUriName.length,
          ...printerUriName,
          (uriLength >> 8) & 0xFF, uriLength & 0xFF,
          ...uriBytes,
          0x03, // End Tag
        ];

        socket.add(Uint8List.fromList(ippHeader));
      } else if (port == 9100) {
        socket.write("\x1B%-12345X@PJL INFO ID\r\n\x1B%-12345X\r\n");
        await socket.flush();
      }

      await completer.future.timeout(const Duration(seconds: 2),
          onTimeout: () {
        subscription.cancel();
      });

      if (buffer.isNotEmpty) {
        final responseBytes = Uint8List.fromList(buffer);

        if (port == 631) {
          String responseString;
          try {
            responseString = utf8.decode(responseBytes, allowMalformed: true);
          } catch (_) {
            responseString = latin1.decode(responseBytes, allowInvalid: true);
          }

          String? extractedName =
              _extractIppAttribute(responseString, 'printer-make-and-model') ??
                  _extractIppAttribute(responseString, 'printer-name');

          if (extractedName != null && extractedName.trim().isNotEmpty) {
            displayName = extractedName.trim();
            final spaceIdx = displayName.indexOf(' ');
            manufacturer =
                spaceIdx != -1 ? displayName.substring(0, spaceIdx) : 'IPP';
            model = spaceIdx != -1
                ? displayName.substring(spaceIdx + 1)
                : displayName;
          }
        } else if (port == 9100) {
          final responseString =
              utf8.decode(responseBytes, allowMalformed: true);
          if (responseString.contains('"')) {
            final parts = responseString.split('"');
            if (parts.length > 1 && parts[1].trim().isNotEmpty) {
              displayName = parts[1].trim();
              final spaceIdx = displayName.indexOf(' ');
              manufacturer =
                  spaceIdx != -1 ? displayName.substring(0, spaceIdx) : 'Raw';
              model = spaceIdx != -1
                  ? displayName.substring(spaceIdx + 1)
                  : displayName;
            }
          }
        }
      }

      final newPrinter = Printer(
        ipAddress: host,
        port: port,
        name: displayName,
        model: model,
        manufacturer: manufacturer,
        status: 'Détectée',
      );

      if (!discoveredPrinters.any((p) => p.ipAddress == host)) {
        discoveredPrinters.add(newPrinter);
        onLog?.call('IMPRIMANTE TROUVÉE : $displayName ($host:$port)', 'success');
        onPrinterDiscovered?.call();
      }
    } catch (_) {
      // Échec silencieux
    } finally {
      try {
        await socket?.close();
      } catch (_) {}
    }
  }

  /// Extrait proprement une chaîne de caractères suite à un attribut textuel IPP
  String? _extractIppAttribute(String response, String attributeName) {
    int idx = response.indexOf(attributeName);
    if (idx == -1) return null;

    int start = idx + attributeName.length;
    if (start >= response.length) return null;

    final sub = response.substring(
        start, (start + 60).clamp(0, response.length));
    final match =
        RegExp(r'[a-zA-Z0-9\s\-\_\.\(\)\/]{3,}').firstMatch(sub);
    return match?.group(0)?.trim();
  }

  Future<bool> connectToPrinter(Printer printer) async {
    try {
      final socket = await Socket.connect(printer.ipAddress, printer.port,
          timeout: const Duration(seconds: 2));
      await socket.close();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Installe le pilote (IPP Everywhere → fallback raw) avec authentification optionnelle.
  Future<PrinterInstallResult> installPrinterDriver(
    Printer printer, {
    String? username,
    String? password,
  }) async {
    if (!Platform.isLinux) {
      return PrinterInstallResult(
        success: false,
        message: "Installation CUPS uniquement disponible sous Linux.",
      );
    }

    try {
      String printerUri;

      if (username != null &&
          username.isNotEmpty &&
          password != null &&
          password.isNotEmpty) {
        final encodedUser = Uri.encodeComponent(username);
        final encodedPass = Uri.encodeComponent(password);
        printerUri = (printer.port == 631)
            ? 'ipp://$encodedUser:$encodedPass@${printer.ipAddress}:631/ipp/print'
            : 'socket://$encodedUser:$encodedPass@${printer.ipAddress}:9100';
      } else {
        printerUri = (printer.port == 631)
            ? 'ipp://${printer.ipAddress}:631/ipp/print'
            : 'socket://${printer.ipAddress}:9100';
      }

      final queueName =
          'FO_Printer_${printer.ipAddress.replaceAll('.', '_')}';

      ProcessResult result = await Process.run(
        'lpadmin',
        ['-p', queueName, '-E', '-v', printerUri, '-m', 'everywhere'],
      );

      if (result.exitCode != 0) {
        result = await Process.run(
          'lpadmin',
          ['-p', queueName, '-E', '-v', printerUri, '-m', 'raw'],
        );
      }

      if (result.exitCode == 0) {
        await Process.run('lpoptions', ['-d', queueName]);
        printer.status = 'Installée & Active';
        return PrinterInstallResult(
          success: true,
          message:
              "Pilote installé. File '$queueName' configurée par défaut.",
          queueName: queueName,
        );
      }

      final stderr = result.stderr.toString().toLowerCase();
      final needsAuth =
          stderr.contains('forbidden') || stderr.contains('unauthorized');

      return PrinterInstallResult(
        success: false,
        message:
            "lpadmin a échoué (code ${result.exitCode}) : ${result.stderr}",
        needsAuth: needsAuth,
      );
    } catch (e) {
      return PrinterInstallResult(
          success: false, message: "Erreur système : $e");
    }
  }

  /// Enchaîne connexion TCP + installation du pilote en une seule opération.
  Future<PrinterInstallResult> connectAndInstall(
    Printer printer, {
    String? username,
    String? password,
    Function(String msg, String type)? onLog,
  }) async {
    onLog?.call(
        "Connexion TCP vers ${printer.ipAddress}:${printer.port}...", 'info');

    final reachable = await connectToPrinter(printer);
    if (!reachable) {
      const msg =
          "Hôte injoignable. Périphérique hors ligne ou port filtré.";
      onLog?.call(msg, 'error');
      return PrinterInstallResult(success: false, message: msg);
    }

    onLog?.call(
        "Liaison établie. Lancement de l'installation du pilote...", 'success');

    final result = await installPrinterDriver(printer,
        username: username, password: password);

    if (result.success) {
      onLog?.call(result.message, 'success');
    } else if (result.needsAuth) {
      onLog?.call("Accès refusé par CUPS. Authentification requise.", 'sys');
    } else {
      onLog?.call("Échec installation : ${result.message}", 'error');
    }

    return result;
  }
}

/// Résultat structuré d'une tentative d'installation de pilote.
class PrinterInstallResult {
  final bool success;
  final String message;
  final bool needsAuth;
  final String? queueName;

  PrinterInstallResult({
    required this.success,
    required this.message,
    this.needsAuth = false,
    this.queueName,
  });
}