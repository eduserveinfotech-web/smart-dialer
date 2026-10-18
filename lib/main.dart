import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const DialerApp());

// ─────────────────────────────────────────────────────────────
// Design tokens
// ─────────────────────────────────────────────────────────────
class Palette {
  static const paper = Color(0xFFF1F4F2); // cool mineral white
  static const ink = Color(0xFF13302A); // deep green-black text
  static const inkSoft = Color(0xFF5E7570); // secondary text
  static const key = Color(0xFFE0E8E4); // keypad / chips
  static const accept = Color(0xFF1E9E6A);
  static const reject = Color(0xFFD64540);
  static const ai = Color(0xFF5B4BDB); // the one distinctive accent
  static const night = Color(0xFF0E1B19); // call screens
}

class DialerApp extends StatelessWidget {
  const DialerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dialer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Palette.accept,
          surface: Palette.paper,
        ),
        scaffoldBackgroundColor: Palette.paper,
        textTheme: ThemeData.light().textTheme.apply(
              bodyColor: Palette.ink,
              displayColor: Palette.ink,
            ),
        navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: Palette.paper,
          indicatorColor: Palette.key,
          elevation: 0,
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith(
              (st) => st.contains(WidgetState.selected) ? Colors.white : null),
          trackColor: WidgetStateProperty.resolveWith(
              (st) => st.contains(WidgetState.selected) ? Palette.ai : null),
        ),
      ),
      home: const HomeShell(),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Models + helpers
// ─────────────────────────────────────────────────────────────
enum CallType { incoming, outgoing, missed }

enum CallAction { accept, reject, ai }

class CallRecord {
  const CallRecord({
    required this.name,
    required this.number,
    required this.type,
    required this.time,
    this.aiSummary,
  });

  final String name; // empty when the number isn't in contacts
  final String number;
  final CallType type;
  final DateTime time;
  final String? aiSummary; // set when the AI assistant answered this call
}

String whenLabel(DateTime t) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(t.year, t.month, t.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m ${t.hour < 12 ? 'AM' : 'PM'}';
  }
  if (diff == 1) return 'Yesterday';
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return days[t.weekday - 1];
}

String initialsOf(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
  return parts.take(2).map((p) => p[0].toUpperCase()).join();
}

// ─────────────────────────────────────────────────────────────
// Home: keypad + recents
// ─────────────────────────────────────────────────────────────
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;
  String _digits = '';
  bool _autoAi = true;

  // Saved contacts, matched on the last 10 digits. In production replace this
  // with the phone's real contacts (e.g. the flutter_contacts package).
  final Map<String, String> _contacts = {
    '9876543210': 'Priya Sharma',
    '9415022817': 'Dad',
    '9988776655': 'Rohan Verma',
    '5422550101': 'City Pharmacy',
  };

  String? _contactName(String number) {
    final d = number.replaceAll(RegExp(r'\D'), '');
    return _contacts[d.length > 10 ? d.substring(d.length - 10) : d];
  }

  late final List<CallRecord> _calls = [
    CallRecord(
      name: 'Priya Sharma',
      number: '+91 98765 43210',
      type: CallType.missed,
      time: DateTime.now().subtract(const Duration(minutes: 38)),
    ),
    CallRecord(
      name: 'Dad',
      number: '+91 94150 22817',
      type: CallType.outgoing,
      time: DateTime.now().subtract(const Duration(hours: 3)),
    ),
    CallRecord(
      name: '',
      number: '+91 80123 45678',
      type: CallType.incoming,
      time: DateTime.now().subtract(const Duration(days: 1, hours: 2)),
      aiSummary:
          'Delivery agent needs your gate number. Told him you will call back.',
    ),
    CallRecord(
      name: 'Rohan Verma',
      number: '+91 99887 76655',
      type: CallType.missed,
      time: DateTime.now().subtract(const Duration(days: 2)),
    ),
    CallRecord(
      name: 'City Pharmacy',
      number: '+91 542 255 0101',
      type: CallType.outgoing,
      time: DateTime.now().subtract(const Duration(days: 4)),
    ),
  ];

  void _log(String number, CallType type,
      {String name = '', String? aiSummary}) {
    setState(() {
      _calls.insert(
        0,
        CallRecord(
          name: name,
          number: number,
          type: type,
          time: DateTime.now(),
          aiSummary: aiSummary,
        ),
      );
    });
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ));
  }

  void _addDigit(String d) {
    HapticFeedback.selectionClick();
    if (_digits.length >= 20) return;
    setState(() => _digits += d);
  }

  void _backspace() {
    if (_digits.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() => _digits = _digits.substring(0, _digits.length - 1));
  }

  void _callNumber(String number, {String name = ''}) {
    if (number.isEmpty) return;
    // TODO: place a real call (url_launcher `tel:` or a ConnectionService
    // integration on Android).
    _log(number, CallType.outgoing,
        name: name.isEmpty ? (_contactName(number) ?? '') : name);
    setState(() => _digits = '');
    _toast('Calling ${name.isEmpty ? number : name}');
  }

  // TODO: replace with a real summary generated by your LLM after the call.
  static const _sampleAiSummary =
      'Caller wants a callback about tomorrow’s plan. Nothing urgent.';

  Future<void> _simulateIncoming(String number) async {
    final name = _contactName(number) ?? '';
    final isSaved = name.isNotEmpty;

    // Unknown number + auto-answer ON -> the AI picks up straight away,
    // no ringing screen. Saved contacts always get the 3-button screen.
    if (!isSaved && _autoAi) {
      await _runAiCall(name, number, autoAnswered: true);
      return;
    }

    final action = await Navigator.of(context).push<CallAction>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => IncomingCallScreen(name: name, number: number),
      ),
    );
    if (!mounted || action == null) return;

    switch (action) {
      case CallAction.accept:
        _log(number, CallType.incoming, name: name);
        _toast('Call connected');
      case CallAction.reject:
        _log(number, CallType.missed, name: name);
        _toast('Call declined');
      case CallAction.ai:
        await _runAiCall(name, number, autoAnswered: false);
    }
  }

  Future<void> _runAiCall(String name, String number,
      {required bool autoAnswered}) async {
    final result = await Navigator.of(context).push<CallAction>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => AiAnswerScreen(
          name: name,
          number: number,
          autoAnswered: autoAnswered,
        ),
      ),
    );
    if (!mounted) return;
    if (result == CallAction.accept) {
      _log(number, CallType.incoming, name: name);
      _toast('You took over the call');
    } else {
      _log(number, CallType.incoming,
          name: name, aiSummary: _sampleAiSummary);
      _toast('AI call ended. Summary saved in Recents');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: _tab,
          children: [
            KeypadPage(
              digits: _digits,
              onDigit: _addDigit,
              onBackspace: _backspace,
              onClear: () => setState(() => _digits = ''),
              onCall: () => _callNumber(_digits),
            ),
            RecentsPage(
              calls: _calls,
              onCall: (c) => _callNumber(c.number, name: c.name),
              onSimulateIncoming: _simulateIncoming,
              autoAi: _autoAi,
              onAutoAiChanged: (v) => setState(() => _autoAi = v),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dialpad_outlined),
            selectedIcon: Icon(Icons.dialpad),
            label: 'Keypad',
          ),
          NavigationDestination(
            icon: Icon(Icons.history),
            selectedIcon: Icon(Icons.history_toggle_off),
            label: 'Recents',
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Keypad
// ─────────────────────────────────────────────────────────────
class KeypadPage extends StatelessWidget {
  const KeypadPage({
    super.key,
    required this.digits,
    required this.onDigit,
    required this.onBackspace,
    required this.onClear,
    required this.onCall,
  });

  final String digits;
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback onClear;
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Center(
              child: digits.isEmpty
                  ? const Text(
                      'Enter a number',
                      style: TextStyle(
                        fontSize: 20,
                        color: Palette.inkSoft,
                        fontWeight: FontWeight.w400,
                      ),
                    )
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        digits,
                        maxLines: 1,
                        style: const TextStyle(
                          fontSize: 44,
                          fontWeight: FontWeight.w300,
                          letterSpacing: 1,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
            ),
          ),
        ),
        DialPad(onKey: onDigit),
        const SizedBox(height: 20),
        Row(
          children: [
            const Expanded(child: SizedBox()),
            RoundAction(
              color: Palette.accept,
              icon: Icons.call,
              label: 'Call',
              size: 72,
              onTap: onCall,
            ),
            Expanded(
              child: Align(
                child: digits.isEmpty
                    ? const SizedBox(height: 48)
                    : GestureDetector(
                        onLongPress: onClear,
                        child: IconButton(
                          tooltip: 'Delete (hold to clear)',
                          iconSize: 28,
                          color: Palette.inkSoft,
                          onPressed: onBackspace,
                          icon: const Icon(Icons.backspace_outlined),
                        ),
                      ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class DialPad extends StatelessWidget {
  const DialPad({super.key, required this.onKey});

  final ValueChanged<String> onKey;

  static const _rows = [
    [['1', ''], ['2', 'ABC'], ['3', 'DEF']],
    [['4', 'GHI'], ['5', 'JKL'], ['6', 'MNO']],
    [['7', 'PQRS'], ['8', 'TUV'], ['9', 'WXYZ']],
    [['*', ''], ['0', '+'], ['#', '']],
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final row in _rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final k in row)
                  DialKey(
                    digit: k[0],
                    letters: k[1],
                    onTap: () => onKey(k[0]),
                    // Hold 0 to type "+", like the system dialer.
                    onLongPress: k[0] == '0' ? () => onKey('+') : null,
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class DialKey extends StatelessWidget {
  const DialKey({
    super.key,
    required this.digit,
    required this.letters,
    required this.onTap,
    this.onLongPress,
  });

  final String digit;
  final String letters;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: letters.isEmpty ? digit : '$digit, $letters',
      excludeSemantics: true,
      child: Material(
        color: Palette.key,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          onLongPress: onLongPress,
          child: SizedBox(
            width: 78,
            height: 78,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  digit,
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w400,
                    height: 1.1,
                  ),
                ),
                if (letters.isNotEmpty)
                  Text(
                    letters,
                    style: const TextStyle(
                      fontSize: 10,
                      letterSpacing: 1.4,
                      color: Palette.inkSoft,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Recents
// ─────────────────────────────────────────────────────────────
class RecentsPage extends StatefulWidget {
  const RecentsPage({
    super.key,
    required this.calls,
    required this.onCall,
    required this.onSimulateIncoming,
    required this.autoAi,
    required this.onAutoAiChanged,
  });

  final List<CallRecord> calls;
  final ValueChanged<CallRecord> onCall;
  final ValueChanged<String> onSimulateIncoming;
  final bool autoAi;
  final ValueChanged<bool> onAutoAiChanged;

  @override
  State<RecentsPage> createState() => _RecentsPageState();
}

class _RecentsPageState extends State<RecentsPage> {
  bool _missedOnly = false;

  void _showSummary(BuildContext context, CallRecord r) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Palette.paper,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.auto_awesome, color: Palette.ai, size: 20),
                SizedBox(width: 8),
                Text(
                  'AI call summary',
                  style: TextStyle(
                    color: Palette.ai,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              r.name.isEmpty ? r.number : r.name,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            ),
            Text(
              '${r.number} · ${whenLabel(r.time)}',
              style: const TextStyle(color: Palette.inkSoft),
            ),
            const SizedBox(height: 16),
            Text(
              r.aiSummary!,
              style: const TextStyle(fontSize: 16, height: 1.4),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  widget.onCall(r);
                },
                style: FilledButton.styleFrom(
                  backgroundColor: Palette.accept,
                  minimumSize: const Size.fromHeight(52),
                ),
                icon: const Icon(Icons.call),
                label: const Text('Call back'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _missedOnly
        ? widget.calls.where((c) => c.type == CallType.missed).toList()
        : widget.calls;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 8, 4),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Recents',
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.w600),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Simulate incoming call',
                icon: const Icon(Icons.phone_callback_outlined),
                onSelected: widget.onSimulateIncoming,
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: '+91 98765 43210',
                    child: Text('Saved contact calls'),
                  ),
                  PopupMenuItem(
                    value: '+91 70001 23456',
                    child: Text('Unknown number calls'),
                  ),
                ],
              ),
            ],
          ),
        ),
        SwitchListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 24),
          secondary: const Icon(Icons.auto_awesome, color: Palette.ai),
          title: const Text('AI answers unknown numbers'),
          subtitle: const Text('Saved contacts still ring normally'),
          value: widget.autoAi,
          onChanged: widget.onAutoAiChanged,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('All'),
                selected: !_missedOnly,
                onSelected: (_) => setState(() => _missedOnly = false),
              ),
              ChoiceChip(
                label: const Text('Missed'),
                selected: _missedOnly,
                onSelected: (_) => setState(() => _missedOnly = true),
              ),
            ],
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? const Center(
                  child: Text(
                    'No missed calls',
                    style: TextStyle(color: Palette.inkSoft, fontSize: 16),
                  ),
                )
              : ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, i) => _CallTile(
                    record: items[i],
                    onCall: () => widget.onCall(items[i]),
                    onOpen: items[i].aiSummary == null
                        ? () => widget.onCall(items[i])
                        : () => _showSummary(context, items[i]),
                  ),
                ),
        ),
      ],
    );
  }
}

class _CallTile extends StatelessWidget {
  const _CallTile({
    required this.record,
    required this.onCall,
    required this.onOpen,
  });

  final CallRecord record;
  final VoidCallback onCall;
  final VoidCallback onOpen; // opens the AI summary, or redials

  @override
  Widget build(BuildContext context) {
    final missed = record.type == CallType.missed;
    final title = record.name.isEmpty ? record.number : record.name;
    final viaAi = record.aiSummary != null;
    final icon = switch (record.type) {
      CallType.incoming => Icons.call_received,
      CallType.outgoing => Icons.call_made,
      CallType.missed => Icons.call_missed,
    };

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      onTap: onOpen,
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: Palette.key,
        foregroundColor: Palette.ink,
        child: record.name.isEmpty
            ? const Icon(Icons.person_outline)
            : Text(
                initialsOf(record.name),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w500,
          color: missed ? Palette.reject : Palette.ink,
        ),
      ),
      subtitle: Row(
        children: [
          Icon(
            viaAi ? Icons.auto_awesome : icon,
            size: 15,
            color: viaAi
                ? Palette.ai
                : (missed ? Palette.reject : Palette.inkSoft),
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              viaAi
                  ? record.aiSummary!
                  : (record.name.isEmpty
                      ? whenLabel(record.time)
                      : record.number),
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Palette.inkSoft),
            ),
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (record.name.isNotEmpty || viaAi)
            Text(
              whenLabel(record.time),
              style: const TextStyle(color: Palette.inkSoft, fontSize: 13),
            ),
          IconButton(
            tooltip: 'Call $title',
            onPressed: onCall,
            color: Palette.accept,
            icon: const Icon(Icons.call_outlined),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Incoming call: Accept / Reject / Answer with AI
// ─────────────────────────────────────────────────────────────
class IncomingCallScreen extends StatelessWidget {
  const IncomingCallScreen({super.key, required this.name, required this.number});

  final String name;
  final String number;

  void _close(BuildContext context, CallAction action) {
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop(action);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.night,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 32, 28, 36),
          child: Column(
            children: [
              const Text(
                'Incoming call',
                style: TextStyle(color: Colors.white60, fontSize: 16),
              ),
              const Spacer(flex: 2),
              CircleAvatar(
                radius: 62,
                backgroundColor: const Color(0xFF1E3532),
                child: name.isEmpty
                    ? const Icon(Icons.person_outline,
                        size: 56, color: Colors.white70)
                    : Text(
                        initialsOf(name),
                        style: const TextStyle(
                          fontSize: 44,
                          color: Colors.white,
                          fontWeight: FontWeight.w300,
                        ),
                      ),
              ),
              const SizedBox(height: 28),
              Text(
                name.isEmpty ? number : name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 34,
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                name.isEmpty ? 'Unknown number' : number,
                style: const TextStyle(color: Colors.white60, fontSize: 18),
              ),
              const Spacer(flex: 3),

              // The one memorable element: a softly pulsing AI option.
              PulseRing(
                color: Palette.ai,
                radius: 32,
                child: FilledButton.icon(
                  onPressed: () => _close(context, CallAction.ai),
                  style: FilledButton.styleFrom(
                    backgroundColor: Palette.ai,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(60),
                    shape: const StadiumBorder(),
                    textStyle: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('Answer with AI'),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'The assistant picks up and finds out why they’re calling.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
              const SizedBox(height: 40),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  RoundAction(
                    color: Palette.reject,
                    icon: Icons.call_end,
                    label: 'Reject',
                    labelColor: Colors.white,
                    size: 76,
                    onTap: () => _close(context, CallAction.reject),
                  ),
                  RoundAction(
                    color: Palette.accept,
                    icon: Icons.call,
                    label: 'Accept',
                    labelColor: Colors.white,
                    size: 76,
                    onTap: () => _close(context, CallAction.accept),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// AI answering screen (UI shell – wire up your own speech/LLM pipeline)
// ─────────────────────────────────────────────────────────────
class AiAnswerScreen extends StatelessWidget {
  const AiAnswerScreen({
    super.key,
    required this.name,
    required this.number,
    this.autoAnswered = false,
  });

  final String name;
  final String number;
  final bool autoAnswered; // true when the AI picked up without ringing

  // Placeholder transcript. Replace with live speech-to-text output.
  static const _transcript = [
    (false, 'Hi, this is the assistant answering for the person you called. How can I help?'),
    (true, 'Hey, it’s Priya. Can you ask him to call me back about tomorrow’s plan?'),
    (false, 'Sure. I’ll pass that on and he’ll get back to you shortly.'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.night,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.auto_awesome, color: Palette.ai, size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    'AI is answering',
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                name.isEmpty ? number : name,
                style: const TextStyle(
                  fontSize: 30,
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                name.isEmpty
                    ? (autoAnswered
                        ? 'Unknown number · picked up automatically'
                        : 'Unknown number')
                    : number,
                style: const TextStyle(color: Colors.white60),
              ),
              const SizedBox(height: 28),
              Expanded(
                child: ListView.separated(
                  itemCount: _transcript.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final (fromCaller, text) = _transcript[i];
                    return Align(
                      alignment:
                          fromCaller ? Alignment.centerLeft : Alignment.centerRight,
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 300),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: fromCaller
                              ? const Color(0xFF1E3532)
                              : Palette.ai.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Text(
                          text,
                          style: const TextStyle(color: Colors.white, fontSize: 15),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  RoundAction(
                    color: Palette.reject,
                    icon: Icons.call_end,
                    label: 'End',
                    labelColor: Colors.white,
                    size: 72,
                    onTap: () => Navigator.of(context).pop(CallAction.reject),
                  ),
                  RoundAction(
                    color: Palette.accept,
                    icon: Icons.call,
                    label: 'Take over',
                    labelColor: Colors.white,
                    size: 72,
                    onTap: () => Navigator.of(context).pop(CallAction.accept),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Shared widgets
// ─────────────────────────────────────────────────────────────
class RoundAction extends StatelessWidget {
  const RoundAction({
    super.key,
    required this.color,
    required this.icon,
    required this.label,
    required this.onTap,
    this.size = 72,
    this.labelColor,
  });

  final Color color;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final double size;
  final Color? labelColor; // when set, the label is shown under the button

  @override
  Widget build(BuildContext context) {
    final button = Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: color,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, color: Colors.white, size: size * 0.42),
          ),
        ),
      ),
    );

    if (labelColor == null) return button;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        button,
        const SizedBox(height: 10),
        Text(label, style: TextStyle(color: labelColor, fontSize: 15)),
      ],
    );
  }
}

/// Draws a slowly expanding outline around [child]. Stops when the system
/// "reduce motion" setting is on.
class PulseRing extends StatefulWidget {
  const PulseRing({
    super.key,
    required this.child,
    required this.color,
    required this.radius,
  });

  final Widget child;
  final Color color;
  final double radius;

  @override
  State<PulseRing> createState() => _PulseRingState();
}

class _PulseRingState extends State<PulseRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.stop();
      _c.value = 0;
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final t = Curves.easeOut.transform(_c.value);
        final spread = 14.0 * t;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: -spread,
              right: -spread,
              top: -spread,
              bottom: -spread,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(widget.radius + spread),
                    border: Border.all(
                      color: widget.color.withValues(alpha: 0.6 * (1 - t)),
                      width: 2,
                    ),
                  ),
                ),
              ),
            ),
            child!,
          ],
        );
      },
    );
  }
}
