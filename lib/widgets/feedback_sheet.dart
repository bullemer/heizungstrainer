import 'package:flutter/material.dart';
import 'package:heizungstrainer/providers/ecl_provider.dart';
import 'package:heizungstrainer/services/feedback_service.dart';
import 'package:provider/provider.dart';

const _accentOrange = Color(0xFFFFA726);

/// Bottom sheet: send praise, an idea or a problem to the Heizungstrainer team.
class FeedbackSheet extends StatefulWidget {
  const FeedbackSheet({super.key, this.initialKind = FeedbackKind.idea});

  final FeedbackKind initialKind;

  static Future<void> show(BuildContext context, {FeedbackKind kind = FeedbackKind.idea}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF23232B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => FeedbackSheet(initialKind: kind),
    );
  }

  @override
  State<FeedbackSheet> createState() => _FeedbackSheetState();
}

class _FeedbackSheetState extends State<FeedbackSheet> {
  late FeedbackKind _kind = widget.initialKind;
  final _message = TextEditingController();
  final _email = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _message.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final provider = context.read<ECLProvider>();
    final controller = provider.currentControllerDescriptor;
    setState(() {
      _sending = true;
      _error = null;
    });
    final error = await provider.feedbackService.send(
      kind: _kind,
      message: _message.text,
      email: _email.text,
      controllerBrand: controller.brand,
      controllerModel: controller.model,
    );
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _sending = false;
        _error = error;
      });
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('Danke für dein Feedback! Wir lesen jede Nachricht.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.read<ECLProvider>().currentControllerDescriptor;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Feedback senden',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFFECECF0)),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Text(
              'Was gefällt dir, was fehlt, was klappt nicht? Wir sind ein kleines Team '
              'und lesen jede Nachricht.',
              style: TextStyle(fontSize: 13, color: Color(0xFF9E9EA8), height: 1.4),
            ),
            const SizedBox(height: 14),
            SegmentedButton<FeedbackKind>(
              segments: [
                for (final k in FeedbackKind.values)
                  ButtonSegment(value: k, label: Text(k.label, style: const TextStyle(fontSize: 12))),
              ],
              selected: {_kind},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _kind = s.first),
            ),
            const SizedBox(height: 14),
            TextField(
              key: const ValueKey('feedback_message'),
              controller: _message,
              minLines: 4,
              maxLines: 8,
              maxLength: 4000,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: _kind == FeedbackKind.problem
                    ? 'Was ist passiert? Was hast du davor gemacht?'
                    : 'Deine Nachricht …',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('feedback_email'),
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'E-Mail (optional, für Rückfragen)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Mitgesendet werden: App-Version, Android-Version und Reglertyp '
              '(${controller.brand} ${controller.model}). Keine Zugangsdaten, keine Messwerte.',
              style: const TextStyle(fontSize: 11, color: Colors.white54, height: 1.4),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: Color(0xFFEF5350), fontSize: 12.5)),
            ],
            const SizedBox(height: 14),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: _accentOrange,
                foregroundColor: Colors.black,
                minimumSize: const Size.fromHeight(46),
              ),
              onPressed: _sending ? null : _send,
              icon: _sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                    )
                  : const Icon(Icons.send_rounded),
              label: const Text('Senden'),
            ),
          ],
        ),
      ),
    );
  }
}
