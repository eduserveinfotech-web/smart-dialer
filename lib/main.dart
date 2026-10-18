import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
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

enum CallFilter {
  all('All'),
  missed('Missed'),
  dialed('Dialed'),
  received('Received');

  const CallFilter(this.label);
  final String label;
}

class ContactEntry {
  const ContactEntry({required this.name, required this.number});
  final String name;
  final String number;
}

/// Last 10 digits of a number, used to match call-log numbers to contacts.
String numberKey(String n) {
  final d = n.replaceAll(RegExp(r'\D'), '');
  return d.length > 10 ? d.substring(d.length - 10) : d;
}

/// Android CallLog.Calls.TYPE -> our CallType.
CallType callTypeFromAndroid(int t) => switch (t) {
      2 => CallType.outgoing,
      3 || 5 || 6 => CallType.missed, // missed, rejected, blocked
      _ => CallType.incoming, // incoming, voicemail, other
    };

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
/// Talks to MainActivity.kt (real call log, contacts, calling). Android only.
class NativeBridge {
  static const _ch = MethodChannel('smart_dialer/native');

  static bool get available =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<Map<String, bool>> permissionStatus() =>
      _perms('permissionStatus');

  static Future<Map<String, bool>> requestPermissions() =>
      _perms('requestPermissions');

  static Future<Map<String, bool>> _perms(String method) async {
    final r = await _ch.invokeMapMethod<String, bool>(method);
    return r ?? <String, bool>{};
  }

  static Future<List<Map<String, dynamic>>> rows(String method) async {
    final raw = await _ch.invokeListMethod<dynamic>(method) ?? <dynamic>[];
    return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  static Future<void> call(String number) =>
      _ch.invokeMethod<void>('call', {'number': number});
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _tab = 0;
  String _digits = '';
  bool _autoAi = true;

  // Contact lookup (last 10 digits -> name) built from the phone's contacts.
  final Map<String, String> _contacts = {};
  List<ContactEntry> _contactRows = [];
  bool _permissionDenied = false;
  bool _contactsDenied = false;
  bool _loading = false;

  String? _contactName(String number) {
    final d = number.replaceAll(RegExp(r'\D'), '');
    return _contacts[d.length > 10 ? d.substring(d.length - 10) : d];
  }

  late final List<CallRecord> _calls = NativeBridge.available ? <CallRecord>[] : [
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (NativeBridge.available) {
      _load(askPermission: true);
    } else {
      // Web preview / non-Android: demo contacts only.
      _setContacts(<ContactEntry>[
        const ContactEntry(name: 'Priya Sharma', number: '+91 98765 43210'),
        const ContactEntry(name: 'Dad', number: '+91 94150 22817'),
        const ContactEntry(name: 'Rohan Verma', number: '+91 99887 76655'),
        const ContactEntry(name: 'City Pharmacy', number: '+91 542 255 0101'),
      ]);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back from a call or from Settings: refresh the history.
    if (state == AppLifecycleState.resumed) _load();
  }

  void _setContacts(List<ContactEntry> rows) {
    rows.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    _contactRows = rows;
    _contacts
      ..clear()
      ..addEntries(rows.map((c) => MapEntry(numberKey(c.number), c.name)));
  }

  CallRecord _recordFromRow(Map<String, dynamic> r) {
    final number = (r['number'] as String?) ?? '';
    final cached = (r['name'] as String?) ?? '';
    return CallRecord(
      name: cached.isNotEmpty ? cached : (_contactName(number) ?? ''),
      number: number.isEmpty ? 'Private number' : number,
      type: callTypeFromAndroid((r['type'] as num?)?.toInt() ?? 1),
      time: DateTime.fromMillisecondsSinceEpoch(
          (r['date'] as num?)?.toInt() ?? 0),
    );
  }

  Future<void> _load({bool askPermission = false}) async {
    if (!NativeBridge.available || _loading) return;
    _loading = true;
    try {
      final perms = askPermission
          ? await NativeBridge.requestPermissions()
          : await NativeBridge.permissionStatus();
      final logOk = perms['log'] == true;
      final contactsOk = perms['contacts'] == true;

      final contactRaw = contactsOk
          ? await NativeBridge.rows('getContacts')
          : <Map<String, dynamic>>[];
      final logRaw = logOk
          ? await NativeBridge.rows('getCallLog')
          : <Map<String, dynamic>>[];
      if (!mounted) return;

      final seen = <String>{};
      final contacts = <ContactEntry>[];
      for (final r in contactRaw) {
        final number = (r['number'] as String?) ?? '';
        if (number.isEmpty || !seen.add(numberKey(number))) continue;
        contacts.add(
            ContactEntry(name: (r['name'] as String?) ?? '', number: number));
      }

      setState(() {
        _permissionDenied = !logOk;
        _contactsDenied = !contactsOk;
        if (contactsOk) _setContacts(contacts);
        _calls
          ..clear()
          ..addAll(logRaw.map(_recordFromRow));
      });
    } catch (_) {
      if (mounted) _toast('Could not load call history');
    } finally {
      _loading = false;
    }
  }

  List<ContactEntry> _suggestionsFor(String digits) {
    final d = digits.replaceAll(RegExp(r'\D'), '');
    if (d.length < 2) return const [];
    return _contactRows
        .where((c) => c.number.replaceAll(RegExp(r'\D'), '').contains(d))
        .take(1)
        .toList();
  }

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

  Future<void> _callNumber(String number, {String name = ''}) async {
    if (!RegExp(r'\d').hasMatch(number)) return;
    final who = name.isEmpty ? (_contactName(number) ?? number) : name;

    if (NativeBridge.available) {
      try {
        await NativeBridge.call(number);
        if (mounted) setState(() => _digits = '');
      } catch (_) {
        if (mounted) _toast('Could not place the call');
      }
      return;
    }

    // Web preview: pretend to call and log it.
    _log(number, CallType.outgoing,
        name: name.isEmpty ? (_contactName(number) ?? '') : name);
    setState(() => _digits = '');
    _toast('Calling $who (demo)');
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
              suggestions: _suggestionsFor(_digits),
              onPickSuggestion: (c) => _callNumber(c.number, name: c.name),
            ),
            RecentsPage(
              calls: _calls,
              onCall: (c) => _callNumber(c.number, name: c.name),
              onSimulateIncoming: _simulateIncoming,
              autoAi: _autoAi,
              onAutoAiChanged: (v) => setState(() => _autoAi = v),
              permissionDenied: _permissionDenied,
              onAllowAccess: () => _load(askPermission: true),
              onRefresh: () => _load(),
            ),
            ContactsPage(
              contacts: _contactRows,
              onCall: (c) => _callNumber(c.number, name: c.name),
              permissionDenied: _contactsDenied,
              onAllowAccess: () => _load(askPermission: true),
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
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Contacts',
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
    required this.suggestions,
    required this.onPickSuggestion,
  });

  final String digits;
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback onClear;
  final VoidCallback onCall;
  final List<ContactEntry> suggestions;
  final ValueChanged<ContactEntry> onPickSuggestion;

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
        for (final c in suggestions)
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 28),
            leading: CircleAvatar(
              backgroundColor: Palette.key,
              foregroundColor: Palette.ink,
              child: Text(initialsOf(c.name)),
            ),
            title: Text(c.name),
            subtitle: Text(c.number),
            trailing: const Icon(Icons.call_outlined, color: Palette.accept),
            onTap: () => onPickSuggestion(c),
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
    required this.permissionDenied,
    required this.onAllowAccess,
    required this.onRefresh,
  });

  final List<CallRecord> calls;
  final ValueChanged<CallRecord> onCall;
  final ValueChanged<String> onSimulateIncoming;
  final bool autoAi;
  final ValueChanged<bool> onAutoAiChanged;
  final bool permissionDenied;
  final VoidCallback onAllowAccess;
  final Future<void> Function() onRefresh;

  @override
  State<RecentsPage> createState() => _RecentsPageState();
}

class _RecentsPageState extends State<RecentsPage> {
  CallFilter _filter = CallFilter.all;

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
    final items = widget.calls
        .where((c) => switch (_filter) {
              CallFilter.all => true,
              CallFilter.missed => c.type == CallType.missed,
              CallFilter.dialed => c.type == CallType.outgoing,
              CallFilter.received => c.type == CallType.incoming,
            })
        .toList();

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
              for (final f in CallFilter.values)
                ChoiceChip(
                  label: Text(f.label),
                  selected: _filter == f,
                  onSelected: (_) => setState(() => _filter = f),
                ),
            ],
          ),
        ),
        Expanded(
          child: widget.permissionDenied
              ? _AccessPrompt(
                  message:
                      'Allow access to your call history to see dialed, received and missed calls here.',
                  onAllow: widget.onAllowAccess,
                )
              : RefreshIndicator(
                  onRefresh: widget.onRefresh,
                  child: items.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: const [
                            SizedBox(height: 120),
                            Center(
                              child: Text(
                                'No calls to show',
                                style: TextStyle(
                                    color: Palette.inkSoft, fontSize: 16),
                              ),
                            ),
                          ],
                        )
                      : ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
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


// ─────────────────────────────────────────────────────────────
// Contacts tab + permission prompt
// ─────────────────────────────────────────────────────────────
class _AccessPrompt extends StatelessWidget {
  const _AccessPrompt({required this.message, required this.onAllow});

  final String message;
  final VoidCallback onAllow;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 40, color: Palette.inkSoft),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, height: 1.4),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: onAllow,
              style: FilledButton.styleFrom(backgroundColor: Palette.accept),
              child: const Text('Allow access'),
            ),
            const SizedBox(height: 12),
            const Text(
              'If nothing happens, open Settings, Apps, Smart Dialer, Permissions.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Palette.inkSoft, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class ContactsPage extends StatefulWidget {
  const ContactsPage({
    super.key,
    required this.contacts,
    required this.onCall,
    required this.permissionDenied,
    required this.onAllowAccess,
  });

  final List<ContactEntry> contacts;
  final ValueChanged<ContactEntry> onCall;
  final bool permissionDenied;
  final VoidCallback onAllowAccess;

  @override
  State<ContactsPage> createState() => _ContactsPageState();
}

class _ContactsPageState extends State<ContactsPage> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final qd = _q.replaceAll(RegExp(r'\D'), '');
    final items = widget.contacts
        .where((c) =>
            c.name.toLowerCase().contains(q) ||
            (qd.isNotEmpty &&
                c.number.replaceAll(RegExp(r'\D'), '').contains(qd)))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 20, 24, 8),
          child: Text(
            'Contacts',
            style: TextStyle(fontSize: 32, fontWeight: FontWeight.w600),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: TextField(
            onChanged: (v) => setState(() => _q = v),
            decoration: InputDecoration(
              hintText: 'Search name or number',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Palette.key,
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(28),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        Expanded(
          child: widget.permissionDenied && widget.contacts.isEmpty
              ? _AccessPrompt(
                  message: 'Allow access to your contacts to see names here.',
                  onAllow: widget.onAllowAccess,
                )
              : items.isEmpty
                  ? const Center(
                      child: Text(
                        'No contacts found',
                        style: TextStyle(color: Palette.inkSoft, fontSize: 16),
                      ),
                    )
                  : ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (context, i) {
                        final c = items[i];
                        return ListTile(
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 20),
                          leading: CircleAvatar(
                            radius: 22,
                            backgroundColor: Palette.key,
                            foregroundColor: Palette.ink,
                            child: Text(
                              initialsOf(c.name),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          title: Text(c.name),
                          subtitle: Text(
                            c.number,
                            style: const TextStyle(color: Palette.inkSoft),
                          ),
                          trailing: IconButton(
                            tooltip: 'Call ${c.name}',
                            color: Palette.accept,
                            icon: const Icon(Icons.call_outlined),
                            onPressed: () => widget.onCall(c),
                          ),
                          onTap: () => widget.onCall(c),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}
