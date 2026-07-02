import 'package:flutter/material.dart';

import 'module/printer.dart';
import 'module/gestion.dart';

void main() {
  runApp(const FO_printer());
}

class FO_printer extends StatelessWidget {
  const FO_printer({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FO_printer - Management Tool',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF121214),
        cardColor: const Color(0xFF1A1A1E),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFE2121E),
          surface: Color(0xFF1A1A1E),
        ),
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final NetworkPrinterScanner _printerScanner = NetworkPrinterScanner();
  final GestionnaireImprimantes _manager = GestionnaireImprimantes();
  final List<Map<String, String>> _terminalLogs = [];
  final ScrollController _scrollController = ScrollController();
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    _printHeader();
  }

  void _printHeader() {
    _log("Initialisation du noyau FO_PRINTER réussie.", type: 'sys');
    _log("Auditeur réseau prêt pour le scan et l'administration physique CUPS (lpadmin).", type: 'info');
  }

  void _log(String message, {String type = 'info'}) {
    setState(() {
      _terminalLogs.add({'msg': message, 'type': type});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _startNetworkScan() async {
    if (_isScanning) return;

    setState(() {
      _isScanning = true;
    });

    _log("Allocation des sockets et lancement du scan réseau réel...", type: 'sys');

    try {
      await _printerScanner.scanNetwork(
        onLog: (msg, type) => _log(msg, type: type),
        onPrinterDiscovered: () => setState(() {}),
      );

      _log("Scan terminé. ${_printerScanner.discoveredPrinters.length} équipement(s) détecté(s).", type: 'sys');

      if (_printerScanner.discoveredPrinters.isEmpty) {
        _log("Aucune socket d'impression ouverte trouvée sur ce sous-réseau.", type: 'error');
      }
    } catch (e) {
      _log("Interruption système lors du scan : $e", type: 'error');
    } finally {
      setState(() {
        _isScanning = false;
      });
    }
  }

  Future<Map<String, String>?> _showAuthDialog(String printerName) async {
    final userController = TextEditingController();
    final passController = TextEditingController();

    return showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1A1A1E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          title: Row(
            children: [
              const Icon(Icons.lock_outline, color: Color(0xFFE2121E), size: 20),
              const SizedBox(width: 10),
              const Text("Authentification requise", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Cet équipement ($printerName) demande des accès pour l'installation réseau.",
                style: const TextStyle(fontSize: 13, color: Colors.white70),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: userController,
                decoration: InputDecoration(
                  labelText: "Nom d'utilisateur",
                  labelStyle: const TextStyle(fontSize: 13),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: "Mot de passe",
                  labelStyle: const TextStyle(fontSize: 13),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text("Annuler", style: TextStyle(color: Colors.white38, fontSize: 13)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop({
                  'user': userController.text,
                  'pass': passController.text,
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE2121E),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              ),
              child: const Text("Se connecter", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ],
        );
      },
    );
  }


  void _connectAndInstallDevice(Printer printer) async {
    PrinterInstallResult result = await _printerScanner.connectAndInstall(
      printer,
      onLog: (msg, type) => _log(msg, type: type),
    );

    if (result.needsAuth) {
      _log("Demande d'authentification à l'utilisateur...", type: 'sys');
      final credentials = await _showAuthDialog(printer.name);

      if (credentials != null) {
        _log("Nouvelle tentative avec les privilèges fournis...", type: 'info');
        result = await _printerScanner.connectAndInstall(
          printer,
          username: credentials['user'],
          password: credentials['pass'],
          onLog: (msg, type) => _log(msg, type: type),
        );
      } else {
        _log("Installation annulée par l'utilisateur.", type: 'sys');
        return;
      }
    }

    if (result.success) {
      _manager.ajouterImprimante(printer);
      setState(() {});
    }
  }

  void _openGestionScreen() {
    // Synchronise les imprimantes découvertes vers le gestionnaire avant navigation
    for (final p in _printerScanner.discoveredPrinters) {
      if (p.status == "Installée & Active") {
        _manager.ajouterImprimante(p);
      }
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GestionScreen(manager: _manager),
      ),
    );
  }

  IconData _getLogIcon(String type) {
    switch (type) {
      case 'error':
        return Icons.error_outline;
      case 'success':
        return Icons.check_circle_outline;
      case 'sys':
        return Icons.settings_outlined;
      case 'info':
      default:
        return Icons.info_outline;
    }
  }

  Color _getLogColor(String type) {
    switch (type) {
      case 'error':
        return const Color(0xFFFA4D56);
      case 'success':
        return const Color(0xFF24A148);
      case 'sys':
        return const Color(0xFF458FFF);
      case 'info':
      default:
        return Colors.white.withValues(alpha: 0.65);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: Opacity(
                opacity: 0.12,
                child: Image.asset('assets/background.png', fit: BoxFit.cover),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                              width: 4,
                              height: 24,
                              decoration: BoxDecoration(
                                  color: const Color(0xFFE2121E),
                                  borderRadius: BorderRadius.circular(2))),
                          const SizedBox(width: 12),
                          const Text("FO_PRINTER",
                              style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.5)),
                          const SizedBox(width: 8),
                          Text("|  Network Auditor",
                              style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.white.withValues(alpha: 0.4))),
                        ],
                      ),
                      Row(
                        children: [
                          // Bouton Gestionnaire
                          GestureDetector(
                            onTap: _openGestionScreen,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1A1A1E),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.print_outlined,
                                      size: 13,
                                      color: Colors.white.withValues(alpha: 0.5)),
                                  const SizedBox(width: 6),
                                  Text("GESTIONNAIRE",
                                      style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white.withValues(alpha: 0.5))),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          // Badge statut scan
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                                color: _isScanning
                                    ? const Color(0xFF3B1214)
                                    : const Color(0xFF1C241E),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                    color: _isScanning
                                        ? const Color(0xFFFA4D56).withValues(alpha: 0.3)
                                        : const Color(0xFF24A148).withValues(alpha: 0.3))),
                            child: Row(
                              children: [
                                Container(
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: _isScanning
                                            ? const Color(0xFFFA4D56)
                                            : const Color(0xFF24A148))),
                                const SizedBox(width: 8),
                                Text(
                                    _isScanning ? "SCANNING" : "STANDBY",
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: _isScanning
                                            ? const Color(0xFFFA4D56)
                                            : const Color(0xFF24A148))),
                              ],
                            ),
                          ),
                        ],
                      )
                    ],
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: _isScanning ? null : _startNetworkScan,
                    icon: _isScanning
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.radar, size: 18),
                    label: Text(
                        _isScanning
                            ? "RECHERCHE EN COURS..."
                            : "LANCER L'AUDIT RÉSEAU",
                        style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            letterSpacing: 0.5)),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE2121E),
                        foregroundColor: Colors.white,
                        disabledBackgroundColor:
                            Colors.white.withValues(alpha: 0.05),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6)),
                        elevation: 0),
                  ),
                  const SizedBox(height: 24),

                  // ── Imprimantes découvertes ──────────────────────────
                  if (_printerScanner.discoveredPrinters.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          Container(width: 3, height: 14,
                              decoration: BoxDecoration(
                                  color: const Color(0xFFE2121E),
                                  borderRadius: BorderRadius.circular(2))),
                          const SizedBox(width: 8),
                          Text("ÉQUIPEMENTS DÉTECTÉS  ·  ${_printerScanner.discoveredPrinters.length}",
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.2,
                                  color: Colors.white.withValues(alpha: 0.4))),
                        ],
                      ),
                    ),
                    ..._printerScanner.discoveredPrinters.map((printer) {
                      final installed = printer.status == "Installée & Active";
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A1E),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.print_outlined,
                                size: 15,
                                color: installed
                                    ? const Color(0xFF24A148)
                                    : Colors.white.withValues(alpha: 0.35)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(printer.name,
                                      style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white)),
                                  const SizedBox(height: 2),
                                  Text(
                                    "${printer.ipAddress}:${printer.port}  ·  ${printer.manufacturer} ${printer.model}",
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.white.withValues(alpha: 0.35)),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            installed
                                ? Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1C241E),
                                      borderRadius: BorderRadius.circular(3),
                                      border: Border.all(color: const Color(0xFF24A148).withValues(alpha: 0.3)),
                                    ),
                                    child: const Text("INSTALLÉE",
                                        style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF24A148))),
                                  )
                                : GestureDetector(
                                    onTap: _isScanning ? null : () => _connectAndInstallDevice(printer),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFE2121E).withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: const Color(0xFFE2121E).withValues(alpha: 0.4)),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.download_outlined, size: 13, color: Color(0xFFE2121E)),
                                          SizedBox(width: 5),
                                          Text("INSTALLER",
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                  color: Color(0xFFE2121E))),
                                        ],
                                      ),
                                    ),
                                  ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 16),
                  ],

                  // ── Terminal ─────────────────────────────────────────
                  if (_terminalLogs.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          Container(width: 3, height: 14,
                              decoration: BoxDecoration(
                                  color: const Color(0xFF458FFF),
                                  borderRadius: BorderRadius.circular(2))),
                          const SizedBox(width: 8),
                          Text("JOURNAL SYSTÈME",
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.2,
                                  color: Colors.white.withValues(alpha: 0.4))),
                        ],
                      ),
                    ),
                  Expanded(
                    child: ListView.builder(
                      controller: _scrollController,
                      padding: EdgeInsets.zero,
                      itemCount: _terminalLogs.length,
                      itemBuilder: (context, index) {
                        final log = _terminalLogs[index];
                        final color = _getLogColor(log['type']!);
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6.0),
                          child: Row(
                            children: [
                              Icon(_getLogIcon(log['type']!),
                                  color: color, size: 16),
                              const SizedBox(width: 12),
                              Expanded(
                                  child: Text(log['msg']!,
                                      style: TextStyle(
                                          color: log['type'] == 'info'
                                              ? Colors.white.withValues(alpha: 0.85)
                                              : color,
                                          fontSize: 13))),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// PAGE GESTIONNAIRE D'IMPRIMANTES
// ─────────────────────────────────────────────

class GestionScreen extends StatefulWidget {
  final GestionnaireImprimantes manager;
  const GestionScreen({super.key, required this.manager});

  @override
  State<GestionScreen> createState() => _GestionScreenState();
}

class _GestionScreenState extends State<GestionScreen> {
  final List<Map<String, String>> _logs = [];
  final ScrollController _logScroll = ScrollController();
  bool _isBusy = false;

  void _log(String message, {String type = 'info'}) {
    setState(() {
      _logs.add({'msg': message, 'type': type});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScroll.hasClients) {
        _logScroll.animateTo(
          _logScroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<String?> _showFilePickerDialog() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: Row(
          children: [
            const Icon(Icons.insert_drive_file_outlined,
                color: Color(0xFFE2121E), size: 20),
            const SizedBox(width: 10),
            const Text("Chemin du fichier",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: "Chemin absolu (ex: /home/user/doc.pdf)",
            labelStyle: const TextStyle(fontSize: 13),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text("Annuler",
                style: TextStyle(color: Colors.white38, fontSize: 13)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE2121E),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4)),
            ),
            child: const Text("Imprimer",
                style:
                    TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Future<bool?> _showConfirmDialog(String printerName) async {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: Row(
          children: [
            const Icon(Icons.delete_outline,
                color: Color(0xFFFA4D56), size: 20),
            const SizedBox(width: 10),
            const Text("Confirmer la suppression",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          "Supprimer '$printerName' du système CUPS ? Cette action est irréversible.",
          style: const TextStyle(fontSize: 13, color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text("Annuler",
                style: TextStyle(color: Colors.white38, fontSize: 13)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFA4D56),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4)),
            ),
            child: const Text("Supprimer",
                style:
                    TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  void _supprimerImprimante(Printer printer) async {
    final confirmed = await _showConfirmDialog(printer.name);
    if (confirmed != true) return;

    setState(() => _isBusy = true);
    _log("Suppression de '${printer.name}' via lpadmin -x...", type: 'sys');

    final ok = await widget.manager.supprimerImprimante(printer);
    if (ok) {
      _log("Imprimante supprimée du système CUPS avec succès.", type: 'success');
    } else {
      _log("Échec de la suppression. Vérifiez les privilèges lpadmin.", type: 'error');
    }

    setState(() => _isBusy = false);
  }

  void _imprimerFichier(Printer printer) async {
    final path = await _showFilePickerDialog();
    if (path == null || path.isEmpty) return;

    setState(() => _isBusy = true);
    _log("Envoi de '$path' à ${printer.name}...", type: 'info');

    final result = await widget.manager.imprimerFichier(printer, path);
    _log(result.message, type: result.success ? 'success' : 'error');

    setState(() => _isBusy = false);
  }

  void _verifierConnexion(Printer printer) async {
    setState(() => _isBusy = true);
    _log("Test de connexion vers ${printer.ipAddress}:${printer.port}...", type: 'info');

    final ok = await widget.manager.connecterImprimante(printer);
    if (ok) {
      _log("Hôte ${printer.ipAddress} joignable. Liaison active.", type: 'success');
    } else {
      _log("Hôte ${printer.ipAddress} injoignable. Périphérique hors ligne.", type: 'error');
    }

    setState(() => _isBusy = false);
  }

  void _annulerTravaux(Printer printer) async {
    setState(() => _isBusy = true);
    _log("Annulation des travaux en file sur ${printer.name}...", type: 'sys');

    final result = await widget.manager.annulerTravaux(printer);
    _log(result.message, type: result.success ? 'success' : 'error');

    setState(() => _isBusy = false);
  }

  void _afficherStatut(Printer printer) async {
    setState(() => _isBusy = true);
    _log("Interrogation de CUPS pour '${printer.name}'...", type: 'sys');

    final statut = await widget.manager.getStatutDetaille(printer);
    _log(statut, type: 'info');

    setState(() => _isBusy = false);
  }

  IconData _getLogIcon(String type) {
    switch (type) {
      case 'error':
        return Icons.error_outline;
      case 'success':
        return Icons.check_circle_outline;
      case 'sys':
        return Icons.settings_outlined;
      default:
        return Icons.info_outline;
    }
  }

  Color _getLogColor(String type) {
    switch (type) {
      case 'error':
        return const Color(0xFFFA4D56);
      case 'success':
        return const Color(0xFF24A148);
      case 'sys':
        return const Color(0xFF458FFF);
      default:
        return Colors.white.withValues(alpha: 0.65);
    }
  }

  @override
  Widget build(BuildContext context) {
    final printers = widget.manager.imprimantesInstallees;

    return Scaffold(
      backgroundColor: const Color(0xFF121214),
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: Opacity(
                opacity: 0.12,
                child: Image.asset('assets/background.png', fit: BoxFit.cover),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A1A1E),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.08)),
                          ),
                          child: Icon(Icons.arrow_back_ios_new,
                              size: 14,
                              color: Colors.white.withValues(alpha: 0.6)),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Container(
                          width: 4,
                          height: 24,
                          decoration: BoxDecoration(
                              color: const Color(0xFFE2121E),
                              borderRadius: BorderRadius.circular(2))),
                      const SizedBox(width: 12),
                      const Text("FO_PRINTER",
                          style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.5)),
                      const SizedBox(width: 8),
                      Text("|  Gestionnaire",
                          style: TextStyle(
                              fontSize: 14,
                              color: Colors.white.withValues(alpha: 0.4))),
                      const Spacer(),
                      if (_isBusy)
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF458FFF)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Liste des imprimantes
                  if (printers.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A1E),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.06)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.print_disabled_outlined,
                              color: Colors.white.withValues(alpha: 0.25),
                              size: 18),
                          const SizedBox(width: 12),
                          Text(
                            "Aucune imprimante installée. Lancez un audit réseau et installez un équipement.",
                            style: TextStyle(
                                fontSize: 13,
                                color: Colors.white.withValues(alpha: 0.4)),
                          ),
                        ],
                      ),
                    )
                  else
                    ...printers.map((printer) => _PrinterCard(
                          printer: printer,
                          onPrint: () => _imprimerFichier(printer),
                          onDelete: () => _supprimerImprimante(printer),
                          onConnect: () => _verifierConnexion(printer),
                          onStatus: () => _afficherStatut(printer),
                          onCancelJobs: () => _annulerTravaux(printer),
                        )),

                  const SizedBox(height: 20),

                  // Terminal log
                  if (_logs.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          Container(width: 3, height: 14,
                              decoration: BoxDecoration(
                                  color: const Color(0xFF458FFF),
                                  borderRadius: BorderRadius.circular(2))),
                          const SizedBox(width: 8),
                          Text("JOURNAL D'ACTIVITÉ",
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.2,
                                  color: Colors.white.withValues(alpha: 0.4))),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        controller: _logScroll,
                        padding: EdgeInsets.zero,
                        itemCount: _logs.length,
                        itemBuilder: (context, index) {
                          final log = _logs[index];
                          final color = _getLogColor(log['type']!);
                          return Padding(
                            padding:
                                const EdgeInsets.symmetric(vertical: 5.0),
                            child: Row(
                              children: [
                                Icon(_getLogIcon(log['type']!),
                                    color: color, size: 15),
                                const SizedBox(width: 10),
                                Expanded(
                                    child: Text(log['msg']!,
                                        style: TextStyle(
                                            color: log['type'] == 'info'
                                                ? Colors.white
                                                    .withValues(alpha: 0.85)
                                                : color,
                                            fontSize: 13))),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrinterCard extends StatelessWidget {
  final Printer printer;
  final VoidCallback onPrint;
  final VoidCallback onDelete;
  final VoidCallback onConnect;
  final VoidCallback onStatus;
  final VoidCallback onCancelJobs;

  const _PrinterCard({
    required this.printer,
    required this.onPrint,
    required this.onDelete,
    required this.onConnect,
    required this.onStatus,
    required this.onCancelJobs,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1E),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.print_outlined,
                  color: Color(0xFFE2121E), size: 16),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(printer.name,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.white)),
                    const SizedBox(height: 2),
                    Text(
                      "${printer.ipAddress}:${printer.port}  ·  ${printer.manufacturer} ${printer.model}",
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withValues(alpha: 0.4)),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF1C241E),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(
                      color: const Color(0xFF24A148).withValues(alpha: 0.3)),
                ),
                child: Text(printer.status,
                    style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF24A148))),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ActionButton(
                icon: Icons.print,
                label: "Imprimer",
                onTap: onPrint,
                color: const Color(0xFF458FFF),
              ),
              _ActionButton(
                icon: Icons.link,
                label: "Tester connexion",
                onTap: onConnect,
                color: Colors.white.withValues(alpha: 0.5),
              ),
              _ActionButton(
                icon: Icons.info_outline,
                label: "Statut CUPS",
                onTap: onStatus,
                color: Colors.white.withValues(alpha: 0.5),
              ),
              _ActionButton(
                icon: Icons.cancel_outlined,
                label: "Annuler travaux",
                onTap: onCancelJobs,
                color: const Color(0xFFFFB800),
              ),
              _ActionButton(
                icon: Icons.delete_outline,
                label: "Supprimer",
                onTap: onDelete,
                color: const Color(0xFFFA4D56),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: color)),
          ],
        ),
      ),
    );
  }
}