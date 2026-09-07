/// Quick diagnostic probe — wide scan of ECL 310 register space.
library;

import 'package:flutter/material.dart';
import 'package:modbus_client/modbus_client.dart';
import 'package:modbus_client_tcp/modbus_client_tcp.dart';

void main() {
  runApp(const RegisterProbeApp());
}

class RegisterProbeApp extends StatelessWidget {
  const RegisterProbeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('ECL 310 Wide Probe')),
        body: const RegisterProbeWidget(),
      ),
    );
  }
}

class RegisterProbeWidget extends StatefulWidget {
  const RegisterProbeWidget({super.key});

  @override
  State<RegisterProbeWidget> createState() => _RegisterProbeWidgetState();
}

class _RegisterProbeWidgetState extends State<RegisterProbeWidget> {
  final List<String> _log = [];
  bool _running = false;

  void _addLog(String msg) {
    setState(() => _log.add(msg));
    debugPrint(msg);
  }

  Future<void> _runProbe() async {
    setState(() { _log.clear(); _running = true; });
    const ip = '192.168.188.133';
    ModbusClientTcp? client;

    try {
      client = ModbusClientTcp(ip, unitId: 1);
      final connected = await client.connect();
      _addLog('Connected to $ip: $connected');
      if (!connected) { _addLog('ERROR: Could not connect'); return; }

      // Wide scan ranges
      final ranges = <String, List<int>>{
        'Sensors S1-S16 (10200-10216)': List.generate(17, (i) => 10200 + i),
        'Scaled sensors (11200-11216)': List.generate(17, (i) => 11200 + i),
        'System params (11000-11050)': List.generate(51, (i) => 11000 + i),
        'Config block (11100-11150)': List.generate(51, (i) => 11100 + i),
        'Extended (11150-11200)': List.generate(51, (i) => 11150 + i),
        'App params (10100-10200)': List.generate(101, (i) => 10100 + i),
        'Schedules? (10300-10350)': List.generate(51, (i) => 10300 + i),
        'Low (0-50)': List.generate(51, (i) => i),
        'Mid (1000-1050)': List.generate(51, (i) => 1000 + i),
        'System (4000-4020)': List.generate(21, (i) => 4000 + i),
      };

      for (final entry in ranges.entries) {
        _addLog('\n── ${entry.key} ──');
        for (final addr in entry.value) {
          final reg = ModbusInt16Register(
            name: 'p$addr', type: ModbusElementType.holdingRegister, address: addr,
          );
          try {
            final resp = await client.send(reg.getReadRequest())
                .timeout(const Duration(seconds: 2));
            if (resp == ModbusResponseCode.requestSucceed) {
              final val = reg.value;
              _addLog('  ✅ $addr → $val '
                  '(÷10=${(val is num ? (val/10).toStringAsFixed(1) : '?')}  '
                  '÷100=${(val is num ? (val/100).toStringAsFixed(2) : '?')})');
            }
          } catch (_) {}
        }
      }
      _addLog('\n═══ WIDE PROBE COMPLETE ═══');
    } catch (e) { _addLog('FATAL: $e'); }
    finally { try { await client?.disconnect(); } catch (_) {} setState(() => _running = false); }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(padding: const EdgeInsets.all(16), child: FilledButton.icon(
        onPressed: _running ? null : _runProbe,
        icon: _running ? const SizedBox(width: 18, height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.search),
        label: Text(_running ? 'Scanning…' : 'Wide Scan ECL 310'),
      )),
      Expanded(child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16), itemCount: _log.length,
        itemBuilder: (_, i) => Text(_log[i], style: TextStyle(
          fontFamily: 'monospace', fontSize: 11,
          color: _log[i].contains('✅') ? Colors.green : null,
        )),
      )),
    ]);
  }
}
