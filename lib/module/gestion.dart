import 'printer.dart';
import 'dart:io';

class GestionnaireImprimantes {
  final List<Printer> imprimantesInstallees = [];
  // FIX: on délègue l'installation au scanner pour éviter la duplication de logique
  final NetworkPrinterScanner _scanner = NetworkPrinterScanner();

  void ajouterImprimante(Printer printer) {
    if (!imprimantesInstallees.any((p) => p.ipAddress == printer.ipAddress)) {
      imprimantesInstallees.add(printer);
    }
  }

  /// Supprime une imprimante du système via lpadmin -x
  Future<bool> supprimerImprimante(Printer printer) async {
    if (!Platform.isLinux) return false;
    try {
      final queueName =
          'FO_Printer_${printer.ipAddress.replaceAll('.', '_')}';
      final result = await Process.run('lpadmin', ['-x', queueName]);
      if (result.exitCode == 0) {
        imprimantesInstallees
            .removeWhere((p) => p.ipAddress == printer.ipAddress);
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Vérifie si une imprimante est déjà installée sur le système CUPS
  Future<bool> estInstallee(Printer printer) async {
    if (!Platform.isLinux) return false;
    try {
      final queueName =
          'FO_Printer_${printer.ipAddress.replaceAll('.', '_')}';
      final result = await Process.run('lpstat', ['-p', queueName]);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Installe le pilote d'une imprimante — délègue à [NetworkPrinterScanner]
  /// pour éviter la duplication de logique avec printer.dart.
  Future<GestionResult> installerDriver(
    Printer printer, {
    String? username,
    String? password,
  }) async {
    final result = await _scanner.installPrinterDriver(
      printer,
      username: username,
      password: password,
    );

    if (result.success) {
      if (!imprimantesInstallees
          .any((p) => p.ipAddress == printer.ipAddress)) {
        imprimantesInstallees.add(printer);
      }
    }

    return GestionResult(
      success: result.success,
      message: result.message,
      needsAuth: result.needsAuth,
    );
  }

  /// Imprime un fichier local sur une imprimante installée
  Future<GestionResult> imprimerFichier(
      Printer printer, String filePath) async {
    if (!Platform.isLinux) {
      return GestionResult(
          success: false,
          message: "Impression CUPS uniquement disponible sous Linux.");
    }

    final file = File(filePath);
    if (!await file.exists()) {
      return GestionResult(
          success: false, message: "Fichier introuvable : $filePath");
    }

    try {
      final queueName =
          'FO_Printer_${printer.ipAddress.replaceAll('.', '_')}';
      final result = await Process.run('lp', ['-d', queueName, filePath]);
      if (result.exitCode == 0) {
        return GestionResult(
          success: true,
          message:
              "Fichier '${filePath.split('/').last}' envoyé à la file '$queueName'.",
        );
      }
      return GestionResult(
        success: false,
        message: "Erreur lp (code ${result.exitCode}) : ${result.stderr}",
      );
    } catch (e) {
      return GestionResult(
          success: false, message: "Erreur lors de l'impression : $e");
    }
  }

  /// Récupère le statut détaillé d'une imprimante via lpstat
  Future<String> getStatutDetaille(Printer printer) async {
    if (!Platform.isLinux) return "Non disponible";
    try {
      final queueName =
          'FO_Printer_${printer.ipAddress.replaceAll('.', '_')}';
      final result =
          await Process.run('lpstat', ['-p', queueName, '-l']);
      if (result.exitCode == 0 && result.stdout.toString().isNotEmpty) {
        return result.stdout.toString().trim();
      }
      return "File d'attente '$queueName' introuvable dans CUPS.";
    } catch (_) {
      return "Impossible de récupérer le statut.";
    }
  }

  /// Annule tous les travaux en attente sur une imprimante
  Future<GestionResult> annulerTravaux(Printer printer) async {
    if (!Platform.isLinux) {
      return GestionResult(
          success: false,
          message: "Annulation CUPS uniquement disponible sous Linux.");
    }
    try {
      final queueName =
          'FO_Printer_${printer.ipAddress.replaceAll('.', '_')}';
      final result = await Process.run('cancel', ['-a', queueName]);
      if (result.exitCode == 0) {
        return GestionResult(
            success: true,
            message: "Tous les travaux annulés sur '$queueName'.");
      }
      return GestionResult(
          success: false,
          message: "Aucun travail à annuler ou file inconnue.");
    } catch (e) {
      return GestionResult(success: false, message: "Erreur : $e");
    }
  }

  Future<bool> connecterImprimante(Printer printer) async {
    try {
      final socket = await Socket.connect(printer.ipAddress, printer.port,
          timeout: const Duration(seconds: 2));
      await socket.close();
      return true;
    } catch (e) {
      return false;
    }
  }
}

class GestionResult {
  final bool success;
  final String message;
  final bool needsAuth;

  GestionResult({
    required this.success,
    required this.message,
    this.needsAuth = false,
  });
}