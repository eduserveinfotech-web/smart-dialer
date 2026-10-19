import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  // The Android in-call screen runs in its own engine started at "/incall".
  final route = PlatformDispatcher.instance.defaultRouteName;
  runApp(route == '/incall' ? const InCallApp() : const DialerApp());
}

// ─────────────────────────────────────────────────────────────
// Design tokens
// ─────────────────────────────────────────────────────────────
class Pal {
  static const violet = Color(0xFF6C3BFF);
  static const indigo = Color(0xFF3D5AFE);
  static const magenta = Color(0xFFFF3D9A);
  static const orange = Color(0xFFFF8A3D);
  static const teal = Color(0xFF00C2A8);
  static const sky = Color(0xFF29B6FF);
  static const green = Color(0xFF18C964);
  static const red = Color(0xFFFF3B4E);
  static const bg = Color(0xFFF5F3FF);
  static const ink = Color(0xFF1B1446);
  static const soft = Color(0xFF6E6A8F);

  static const brand = LinearGradient(
    colors: [violet, magenta],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const callBg = LinearGradient(
    colors: [Color(0xFF160F3D), Color(0xFF4B2AA8), Color(0xFFC13584)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
  static const avatars = <List<Color>>[
    [violet, indigo],
    [magenta, orange],
    [teal, sky],
    [orange, magenta],
    [indigo, sky],
    [green, teal],
  ];
}

class DialerApp extends StatelessWidget {
  const DialerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Dialer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Pal.violet,
          surface: Pal.bg,
        ),
        scaffoldBackgroundColor: Pal.bg,
        textTheme: ThemeData.light()
            .textTheme
            .apply(bodyColor: Pal.ink, displayColor: Pal.ink),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: Colors.white,
          elevation: 8,
          indicatorColor: Pal.violet.withValues(alpha: 0.14),
        ),
      ),
      home: const HomeShell(),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Models + helpers
// ─────────────────────────────────────────────────────────────
enum CallKind { incoming, outgoing, missed }

enum CallFilter {
  all('All'),
  missed('Missed'),
  dialed('Dialed'),
  received('Received');

  const CallFilter(this.label);
  final String label;
}

class CallRecord {
  const CallRecord({
    required this.name,
    required this.number,
    required this.kind,
    required this.time,
  });
  final String name;
  final String number;
  final CallKind kind;
  final DateTime time;
}

class ContactEntry {
  const ContactEntry({required this.name, required this.number});
  final String name;
  final String number;
}

class SmsThread {
  const SmsThread({
    required this.threadId,
    required this.address,
    required this.body,
    required this.date,
    required this.unread,
    required this.mine,
  });
  final int threadId;
  final String address;
  final String body;
  final DateTime date;
  final int unread;
  final bool mine;
}

class SmsMsg {
  const SmsMsg({required this.body, required this.date, required this.mine});
  final String body;
  final DateTime date;
  final bool mine;
}

class AppSettings {
  const AppSettings({
    this.isDialer = false,
    this.isCallerId = false,
    this.silenceUnknown = false,
    this.blocked = const [],
  });
  final bool isDialer;
  final bool isCallerId;
  final bool silenceUnknown;
  final List<String> blocked;

  AppSettings copyWith({bool? silenceUnknown, List<String>? blocked}) =>
      AppSettings(
        isDialer: isDialer,
        isCallerId: isCallerId,
        silenceUnknown: silenceUnknown ?? this.silenceUnknown,
        blocked: blocked ?? this.blocked,
      );

  factory AppSettings.fromMap(Map<String, dynamic> m) => AppSettings(
        isDialer: m['isDialer'] == true,
        isCallerId: m['isCallerId'] == true,
        silenceUnknown: m['silenceUnknown'] == true,
        blocked: ((m['blocked'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
      );
}

String initialsOf(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
  return parts.take(2).map((p) => p[0].toUpperCase()).join();
}

String numberKey(String n) {
  final d = n.replaceAll(RegExp(r'\D'), '');
  return d.length > 10 ? d.substring(d.length - 10) : d;
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

String fmtDuration(Duration d) {
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
}

List<Color> gradientFor(String seed) =>
    Pal.avatars[seed.codeUnits.fold<int>(0, (a, b) => a + b) % Pal.avatars.length];

CallKind callKindFromAndroid(int t) => switch (t) {
      2 => CallKind.outgoing,
      3 || 5 || 6 => CallKind.missed,
      _ => CallKind.incoming,
    };

class GradientAvatar extends StatelessWidget {
  const GradientAvatar({
    super.key,
    required this.name,
    required this.seed,
    this.radius = 24,
  });
  final String name;
  final String seed;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: radius * 2,
      height: radius * 2,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: gradientFor(seed),
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: name.isEmpty
          ? Icon(Icons.person, color: Colors.white, size: radius)
          : Text(
              initialsOf(name),
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: radius * 0.75,
              ),
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Native bridge (MainActivity.kt). Android only.
// ─────────────────────────────────────────────────────────────
class NativeBridge {
  static const _ch = MethodChannel('smart_dialer/native');

  static bool get available =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<Map<String, bool>> _perms(String m) async {
    final r = await _ch.invokeMapMethod<String, bool>(m);
    return r ?? <String, bool>{};
  }

  static Future<Map<String, bool>> permissionStatus() =>
      _perms('permissionStatus');
  static Future<Map<String, bool>> requestPermissions() =>
      _perms('requestPermissions');

  static Future<List<Map<String, dynamic>>> rows(String method,
      [Map<String, dynamic>? args]) async {
    final raw = await _ch.invokeListMethod<dynamic>(method, args) ?? <dynamic>[];
    return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  static Future<void> call(String number) =>
      _ch.invokeMethod<void>('call', {'number': number});
  static Future<void> sendSms(String address, String body) =>
      _ch.invokeMethod<void>('sendSms', {'address': address, 'body': body});
  static Future<String?> takeDial() => _ch.invokeMethod<String>('takeDialNumber');

  static Future<AppSettings> settings() async {
    final r = await _ch.invokeMapMethod<String, dynamic>('getSettings');
    return AppSettings.fromMap(r ?? <String, dynamic>{});
  }

  static Future<void> setSilenceUnknown(bool v) =>
      _ch.invokeMethod<void>('setSilenceUnknown', {'value': v});
  static Future<void> setBlocked(List<String> n) =>
      _ch.invokeMethod<void>('setBlocked', {'numbers': n});
  static Future<void> requestDialer() =>
      _ch.invokeMethod<void>('requestDefaultDialer');
  static Future<void> requestCallerId() =>
      _ch.invokeMethod<void>('requestCallerId');
  static Future<void> openAppSettings() =>
      _ch.invokeMethod<void>('openAppSettings');
}

// ─────────────────────────────────────────────────────────────
// Home shell
// ─────────────────────────────────────────────────────────────
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _tab = 0;
  String _digits = '';
  final List<CallRecord> _calls = [];
  final Map<String, String> _contacts = {};
  List<ContactEntry> _contactRows = [];
  List<SmsThread> _threads = [];
  final ValueNotifier<AppSettings> _settings =
      ValueNotifier<AppSettings>(const AppSettings());
  bool _logOk = true;
  bool _contactsOk = true;
  bool _smsOk = true;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (NativeBridge.available) {
      _load(ask: true);
    } else {
      _loadDemo();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  // ----- data -----
  void _setContacts(List<ContactEntry> rows) {
    rows.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    _contactRows = rows;
    _contacts
      ..clear()
      ..addEntries(rows.map((c) => MapEntry(numberKey(c.number), c.name)));
  }

  String _nameFor(String number) => _contacts[numberKey(number)] ?? '';

  void _loadDemo() {
    final now = DateTime.now();
    _setContacts(<ContactEntry>[
      const ContactEntry(name: 'Priya Sharma', number: '+91 98765 43210'),
      const ContactEntry(name: 'Dad', number: '+91 94150 22817'),
      const ContactEntry(name: 'Rohan Verma', number: '+91 99887 76655'),
      const ContactEntry(name: 'City Pharmacy', number: '+91 542 255 0101'),
      const ContactEntry(name: 'Ananya Singh', number: '+91 90123 45678'),
    ]);
    CallRecord c(String n, CallKind k, Duration ago) => CallRecord(
        name: _nameFor(n), number: n, kind: k, time: now.subtract(ago));
    _calls.addAll([
      c('+91 98765 43210', CallKind.missed, const Duration(minutes: 38)),
      c('+91 94150 22817', CallKind.outgoing, const Duration(hours: 3)),
      c('+91 80123 45678', CallKind.incoming, const Duration(days: 1)),
      c('+91 99887 76655', CallKind.missed, const Duration(days: 2)),
      c('+91 542 255 0101', CallKind.outgoing, const Duration(days: 4)),
    ]);
    _threads = [
      SmsThread(
          threadId: 1,
          address: '+91 98765 43210',
          body: 'Call me when you are free',
          date: now.subtract(const Duration(minutes: 20)),
          unread: 2,
          mine: false),
      SmsThread(
          threadId: 2,
          address: '+91 94150 22817',
          body: 'Beta kal aa rahe ho?',
          date: now.subtract(const Duration(hours: 5)),
          unread: 0,
          mine: false),
      SmsThread(
          threadId: 3,
          address: 'AX-DELIVRY',
          body: 'Your parcel is out for delivery today.',
          date: now.subtract(const Duration(days: 1)),
          unread: 1,
          mine: false),
    ];
  }

  Future<void> _load({bool ask = false}) async {
    if (!NativeBridge.available || _loading) return;
    _loading = true;
    try {
      final perms = ask
          ? await NativeBridge.requestPermissions()
          : await NativeBridge.permissionStatus();
      final logOk = perms['log'] == true;
      final contactsOk = perms['contacts'] == true;
      final smsOk = perms['sms'] == true;

      final contactRaw = contactsOk
          ? await NativeBridge.rows('getContacts')
          : <Map<String, dynamic>>[];
      final logRaw =
          logOk ? await NativeBridge.rows('getCallLog') : <Map<String, dynamic>>[];
      final smsRaw = smsOk
          ? await NativeBridge.rows('getSmsThreads')
          : <Map<String, dynamic>>[];
      final settings = await NativeBridge.settings();
      final dial = await NativeBridge.takeDial();
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
        _logOk = logOk;
        _contactsOk = contactsOk;
        _smsOk = smsOk;
        if (contactsOk) _setContacts(contacts);
        _calls
          ..clear()
          ..addAll(logRaw.map((r) {
            final number = (r['number'] as String?) ?? '';
            final cached = (r['name'] as String?) ?? '';
            return CallRecord(
              name: cached.isNotEmpty ? cached : _nameFor(number),
              number: number.isEmpty ? 'Private number' : number,
              kind: callKindFromAndroid((r['type'] as num?)?.toInt() ?? 1),
              time: DateTime.fromMillisecondsSinceEpoch(
                  (r['date'] as num?)?.toInt() ?? 0),
            );
          }));
        _threads = smsRaw
            .map((r) => SmsThread(
                  threadId: (r['threadId'] as num?)?.toInt() ?? -1,
                  address: (r['address'] as String?) ?? '',
                  body: (r['body'] as String?) ?? '',
                  date: DateTime.fromMillisecondsSinceEpoch(
                      (r['date'] as num?)?.toInt() ?? 0),
                  unread: (r['unread'] as num?)?.toInt() ?? 0,
                  mine: ((r['type'] as num?)?.toInt() ?? 1) == 2,
                ))
            .toList();
        _settings.value = settings;
        if (dial != null && dial.isNotEmpty) {
          _digits = dial;
          _tab = 0;
        }
      });
    } catch (_) {
      if (mounted) _toast('Could not load phone data');
    } finally {
      _loading = false;
    }
  }

  // ----- actions -----
  void _toast(String m) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
          SnackBar(content: Text(m), behavior: SnackBarBehavior.floating));
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

  Future<void> _call(String number, {String name = ''}) async {
    if (!RegExp(r'\d').hasMatch(number)) return;
    if (NativeBridge.available) {
      try {
        await NativeBridge.call(number);
        if (mounted) setState(() => _digits = '');
      } catch (_) {
        if (mounted) _toast('Could not place the call');
      }
      return;
    }
    // Web preview: show the call screen with a demo backend.
    setState(() => _digits = '');
    _previewCall(incoming: false, number: number, name: name.isEmpty ? _nameFor(number) : name);
  }

  List<ContactEntry> _suggestions() {
    final d = _digits.replaceAll(RegExp(r'\D'), '');
    if (d.length < 2) return const [];
    return _contactRows
        .where((c) => c.number.replaceAll(RegExp(r'\D'), '').contains(d))
        .take(1)
        .toList();
  }

  Future<void> _openChat(String address, {SmsThread? thread}) async {
    final title = _nameFor(address).isEmpty ? address : _nameFor(address);
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ChatPage(
        title: title,
        address: address,
        loader: () async {
          if (!NativeBridge.available || thread == null) {
            return thread == null
                ? <SmsMsg>[]
                : [
                    SmsMsg(
                        body: thread.body,
                        date: thread.date,
                        mine: thread.mine),
                  ];
          }
          final raw = await NativeBridge.rows(
              'getSmsMessages', {'threadId': thread.threadId});
          return raw
              .map((r) => SmsMsg(
                    body: (r['body'] as String?) ?? '',
                    date: DateTime.fromMillisecondsSinceEpoch(
                        (r['date'] as num?)?.toInt() ?? 0),
                    mine: ((r['type'] as num?)?.toInt() ?? 1) == 2,
                  ))
              .toList();
        },
        onSend: (body) async {
          if (NativeBridge.available) {
            await NativeBridge.sendSms(address, body);
          }
        },
        onCall: () => _call(address, name: _nameFor(address)),
      ),
    ));
    _load();
  }

  Future<void> _newMessage() async {
    final ctl = TextEditingController();
    final number = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New message'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(hintText: 'Phone number'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctl.text.trim()),
              child: const Text('Chat')),
        ],
      ),
    );
    if (number != null && number.isNotEmpty && mounted) _openChat(number);
  }

  void _toggleBlock(String number) {
    final cur = List<String>.from(_settings.value.blocked);
    final key = numberKey(number);
    final blocked = cur.any((n) => numberKey(n) == key);
    if (blocked) {
      cur.removeWhere((n) => numberKey(n) == key);
    } else {
      cur.add(number);
    }
    _settings.value = _settings.value.copyWith(blocked: cur);
    if (NativeBridge.available) NativeBridge.setBlocked(cur);
    _toast(blocked ? 'Number unblocked' : 'Number blocked');
  }

  void _previewCall(
      {required bool incoming, String number = '+91 98765 43210', String name = 'Priya Sharma'}) {
    final nav = Navigator.of(context);
    final backend = DemoCallBackend(
      incoming: incoming,
      number: number,
      name: name,
      onClose: () {
        if (nav.canPop()) nav.pop();
      },
    );
    nav.push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => InCallScreen(backend: backend),
    ));
  }

  void _openSettings() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => SettingsPage(
        settings: _settings,
        onRequestDialer: () async {
          if (!NativeBridge.available) {
            _toast('This works in the Android app only');
            return;
          }
          await NativeBridge.requestDialer();
        },
        onRequestCallerId: () async {
          if (!NativeBridge.available) {
            _toast('This works in the Android app only');
            return;
          }
          await NativeBridge.requestCallerId();
        },
        onSilence: (v) {
          _settings.value = _settings.value.copyWith(silenceUnknown: v);
          if (NativeBridge.available) NativeBridge.setSilenceUnknown(v);
        },
        onBlockedChanged: (list) {
          _settings.value = _settings.value.copyWith(blocked: list);
          if (NativeBridge.available) NativeBridge.setBlocked(list);
        },
        onOpenAppSettings: () {
          if (NativeBridge.available) NativeBridge.openAppSettings();
        },
        onPreviewIncoming: () => _previewCall(incoming: true),
        onPreviewActive: () => _previewCall(incoming: false),
        onRefresh: () => _load(),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            IndexedStack(
              index: _tab,
              children: [
                KeypadPage(
                  digits: _digits,
                  onDigit: _addDigit,
                  onBackspace: _backspace,
                  onClear: () => setState(() => _digits = ''),
                  onCall: () => _call(_digits),
                  suggestions: _suggestions(),
                  onPick: (c) => _call(c.number, name: c.name),
                ),
                RecentsPage(
                  calls: _calls,
                  blocked: _settings,
                  permissionDenied: !_logOk,
                  onAllow: () => _load(ask: true),
                  onRefresh: () => _load(),
                  onCall: (c) => _call(c.number, name: c.name),
                  onMessage: (c) => _openChat(c.number),
                  onBlock: (c) => _toggleBlock(c.number),
                ),
                ContactsPage(
                  contacts: _contactRows,
                  permissionDenied: !_contactsOk,
                  onAllow: () => _load(ask: true),
                  onCall: (c) => _call(c.number, name: c.name),
                  onMessage: (c) => _openChat(c.number),
                ),
                MessagesPage(
                  threads: _threads,
                  nameFor: _nameFor,
                  permissionDenied: !_smsOk,
                  onAllow: () => _load(ask: true),
                  onRefresh: () => _load(),
                  onOpen: (t) => _openChat(t.address, thread: t),
                  onNew: _newMessage,
                ),
              ],
            ),
            Positioned(
              top: 4,
              right: 8,
              child: IconButton(
                tooltip: 'Settings',
                onPressed: _openSettings,
                icon: const Icon(Icons.tune_rounded, color: Pal.violet),
              ),
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
              selectedIcon: Icon(Icons.dialpad, color: Pal.violet),
              label: 'Keypad'),
          NavigationDestination(
              icon: Icon(Icons.history),
              selectedIcon: Icon(Icons.history, color: Pal.magenta),
              label: 'Recents'),
          NavigationDestination(
              icon: Icon(Icons.people_outline),
              selectedIcon: Icon(Icons.people, color: Pal.teal),
              label: 'Contacts'),
          NavigationDestination(
              icon: Icon(Icons.chat_bubble_outline),
              selectedIcon: Icon(Icons.chat_bubble, color: Pal.orange),
              label: 'Messages'),
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
    required this.onPick,
  });

  final String digits;
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback onClear;
  final VoidCallback onCall;
  final List<ContactEntry> suggestions;
  final ValueChanged<ContactEntry> onPick;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Center(
              child: digits.isEmpty
                  ? ShaderMask(
                      shaderCallback: (r) => Pal.brand.createShader(r),
                      child: const Text(
                        'Smart Dialer',
                        style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            color: Colors.white),
                      ),
                    )
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        digits,
                        maxLines: 1,
                        style: const TextStyle(
                          fontSize: 44,
                          fontWeight: FontWeight.w400,
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
            leading: GradientAvatar(name: c.name, seed: c.number, radius: 18),
            title: Text(c.name),
            subtitle: Text(c.number),
            trailing: const Icon(Icons.call, color: Pal.green),
            onTap: () => onPick(c),
          ),
        DialPad(onKey: onDigit),
        const SizedBox(height: 18),
        Row(
          children: [
            const Expanded(child: SizedBox()),
            GestureDetector(
              onTap: onCall,
              child: Container(
                width: 74,
                height: 74,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                      colors: [Pal.green, Pal.teal],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight),
                  boxShadow: [
                    BoxShadow(
                        color: Pal.green.withValues(alpha: 0.45),
                        blurRadius: 18,
                        offset: const Offset(0, 8)),
                  ],
                ),
                child: const Icon(Icons.call, color: Colors.white, size: 32),
              ),
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
                          color: Pal.soft,
                          onPressed: onBackspace,
                          icon: const Icon(Icons.backspace_outlined),
                        ),
                      ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class DialPad extends StatelessWidget {
  const DialPad({super.key, required this.onKey, this.dark = false, this.size = 74});

  final ValueChanged<String> onKey;
  final bool dark;
  final double size;

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
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final k in row)
                  DialKey(
                    digit: k[0],
                    letters: k[1],
                    dark: dark,
                    size: size,
                    onTap: () => onKey(k[0]),
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
    this.dark = false,
    this.size = 74,
  });

  final String digit;
  final String letters;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool dark;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fg = dark ? Colors.white : Pal.ink;
    return Semantics(
      button: true,
      label: letters.isEmpty ? digit : '$digit, $letters',
      excludeSemantics: true,
      child: Material(
        color: dark ? Colors.white.withValues(alpha: 0.16) : Colors.white,
        elevation: dark ? 0 : 3,
        shadowColor: Pal.violet.withValues(alpha: 0.35),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          onLongPress: onLongPress,
          child: SizedBox(
            width: size,
            height: size,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(digit,
                    style: TextStyle(
                        fontSize: size * 0.4,
                        fontWeight: FontWeight.w500,
                        color: fg,
                        height: 1.1)),
                if (letters.isNotEmpty)
                  Text(letters,
                      style: TextStyle(
                          fontSize: 9,
                          letterSpacing: 1.4,
                          fontWeight: FontWeight.w600,
                          color: dark ? Colors.white70 : Pal.magenta)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Shared page bits
// ─────────────────────────────────────────────────────────────
class PageTitle extends StatelessWidget {
  const PageTitle(this.text, {super.key, this.sub});
  final String text;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 64, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ShaderMask(
            shaderCallback: (r) => Pal.brand.createShader(r),
            child: Text(text,
                style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: Colors.white)),
          ),
          if (sub != null)
            Text(sub!, style: const TextStyle(color: Pal.soft, fontSize: 13)),
        ],
      ),
    );
  }
}

class AccessPrompt extends StatelessWidget {
  const AccessPrompt({super.key, required this.message, required this.onAllow});
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
            Container(
              width: 72,
              height: 72,
              decoration:
                  const BoxDecoration(shape: BoxShape.circle, gradient: Pal.brand),
              child: const Icon(Icons.lock_open_rounded,
                  color: Colors.white, size: 34),
            ),
            const SizedBox(height: 16),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, height: 1.4)),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: onAllow,
              style: FilledButton.styleFrom(backgroundColor: Pal.violet),
              child: const Text('Allow access'),
            ),
            const SizedBox(height: 12),
            const Text(
              'If nothing happens: Settings > Apps > Smart Dialer > Permissions. On some phones also tap the 3 dots and choose "Allow restricted settings".',
              textAlign: TextAlign.center,
              style: TextStyle(color: Pal.soft, fontSize: 12),
            ),
          ],
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
    required this.blocked,
    required this.permissionDenied,
    required this.onAllow,
    required this.onRefresh,
    required this.onCall,
    required this.onMessage,
    required this.onBlock,
  });

  final List<CallRecord> calls;
  final ValueNotifier<AppSettings> blocked;
  final bool permissionDenied;
  final VoidCallback onAllow;
  final Future<void> Function() onRefresh;
  final ValueChanged<CallRecord> onCall;
  final ValueChanged<CallRecord> onMessage;
  final ValueChanged<CallRecord> onBlock;

  @override
  State<RecentsPage> createState() => _RecentsPageState();
}

class _RecentsPageState extends State<RecentsPage> {
  CallFilter _filter = CallFilter.all;

  void _sheet(CallRecord r) {
    final isBlocked = widget.blocked.value.blocked
        .any((n) => numberKey(n) == numberKey(r.number));
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: GradientAvatar(name: r.name, seed: r.number),
              title: Text(r.name.isEmpty ? r.number : r.name,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(r.number),
            ),
            ListTile(
              leading: const Icon(Icons.call, color: Pal.green),
              title: const Text('Call'),
              onTap: () {
                Navigator.pop(ctx);
                widget.onCall(r);
              },
            ),
            ListTile(
              leading: const Icon(Icons.chat_bubble, color: Pal.orange),
              title: const Text('Message'),
              onTap: () {
                Navigator.pop(ctx);
                widget.onMessage(r);
              },
            ),
            ListTile(
              leading: Icon(isBlocked ? Icons.lock_open : Icons.block,
                  color: Pal.red),
              title: Text(isBlocked ? 'Unblock number' : 'Block number'),
              onTap: () {
                Navigator.pop(ctx);
                widget.onBlock(r);
              },
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
              CallFilter.missed => c.kind == CallKind.missed,
              CallFilter.dialed => c.kind == CallKind.outgoing,
              CallFilter.received => c.kind == CallKind.incoming,
            })
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageTitle('Recents', sub: '${widget.calls.length} calls'),
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            children: [
              for (final f in CallFilter.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _filter = f),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        gradient: _filter == f ? Pal.brand : null,
                        color: _filter == f ? null : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(f.label,
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: _filter == f ? Colors.white : Pal.soft)),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: widget.permissionDenied
              ? AccessPrompt(
                  message:
                      'Allow access to your call history to see dialed, received and missed calls.',
                  onAllow: widget.onAllow)
              : RefreshIndicator(
                  onRefresh: widget.onRefresh,
                  child: items.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: const [
                            SizedBox(height: 120),
                            Center(
                                child: Text('No calls to show',
                                    style: TextStyle(color: Pal.soft))),
                          ],
                        )
                      : ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                          itemCount: items.length,
                          itemBuilder: (context, i) => _CallTile(
                            record: items[i],
                            onTap: () => widget.onCall(items[i]),
                            onLong: () => _sheet(items[i]),
                          ),
                        ),
                ),
        ),
      ],
    );
  }
}

class _CallTile extends StatelessWidget {
  const _CallTile(
      {required this.record, required this.onTap, required this.onLong});
  final CallRecord record;
  final VoidCallback onTap;
  final VoidCallback onLong;

  @override
  Widget build(BuildContext context) {
    final missed = record.kind == CallKind.missed;
    final title = record.name.isEmpty ? record.number : record.name;
    final (icon, color) = switch (record.kind) {
      CallKind.incoming => (Icons.call_received, Pal.green),
      CallKind.outgoing => (Icons.call_made, Pal.indigo),
      CallKind.missed => (Icons.call_missed, Pal.red),
    };
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: ListTile(
        onTap: onTap,
        onLongPress: onLong,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        leading: GradientAvatar(name: record.name, seed: record.number),
        title: Text(title,
            style: TextStyle(
                fontWeight: FontWeight.w600,
                color: missed ? Pal.red : Pal.ink)),
        subtitle: Row(
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                record.name.isEmpty ? 'Unknown' : record.number,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Pal.soft),
              ),
            ),
          ],
        ),
        trailing: Text(whenLabel(record.time),
            style: const TextStyle(color: Pal.soft, fontSize: 12)),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Contacts
// ─────────────────────────────────────────────────────────────
class ContactsPage extends StatefulWidget {
  const ContactsPage({
    super.key,
    required this.contacts,
    required this.permissionDenied,
    required this.onAllow,
    required this.onCall,
    required this.onMessage,
  });

  final List<ContactEntry> contacts;
  final bool permissionDenied;
  final VoidCallback onAllow;
  final ValueChanged<ContactEntry> onCall;
  final ValueChanged<ContactEntry> onMessage;

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
        PageTitle('Contacts', sub: '${widget.contacts.length} people'),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: TextField(
            onChanged: (v) => setState(() => _q = v),
            decoration: InputDecoration(
              hintText: 'Search name or number',
              prefixIcon: const Icon(Icons.search, color: Pal.violet),
              filled: true,
              fillColor: Colors.white,
              contentPadding: EdgeInsets.zero,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                  borderSide: BorderSide.none),
            ),
          ),
        ),
        Expanded(
          child: widget.permissionDenied && widget.contacts.isEmpty
              ? AccessPrompt(
                  message: 'Allow access to your contacts to see names here.',
                  onAllow: widget.onAllow)
              : items.isEmpty
                  ? const Center(
                      child: Text('No contacts found',
                          style: TextStyle(color: Pal.soft)))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      itemCount: items.length,
                      itemBuilder: (context, i) {
                        final c = items[i];
                        return Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(18)),
                          child: ListTile(
                            onTap: () => widget.onCall(c),
                            leading:
                                GradientAvatar(name: c.name, seed: c.number),
                            title: Text(c.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            subtitle: Text(c.number,
                                style: const TextStyle(color: Pal.soft)),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Message ${c.name}',
                                  icon: const Icon(Icons.chat_bubble_outline,
                                      color: Pal.orange),
                                  onPressed: () => widget.onMessage(c),
                                ),
                                IconButton(
                                  tooltip: 'Call ${c.name}',
                                  icon: const Icon(Icons.call,
                                      color: Pal.green),
                                  onPressed: () => widget.onCall(c),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Messages (SMS)
// ─────────────────────────────────────────────────────────────
class MessagesPage extends StatelessWidget {
  const MessagesPage({
    super.key,
    required this.threads,
    required this.nameFor,
    required this.permissionDenied,
    required this.onAllow,
    required this.onRefresh,
    required this.onOpen,
    required this.onNew,
  });

  final List<SmsThread> threads;
  final String Function(String) nameFor;
  final bool permissionDenied;
  final VoidCallback onAllow;
  final Future<void> Function() onRefresh;
  final ValueChanged<SmsThread> onOpen;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageTitle('Messages', sub: '${threads.length} conversations'),
            Expanded(
              child: permissionDenied
                  ? AccessPrompt(
                      message: 'Allow access to your SMS to read your messages here.',
                      onAllow: onAllow)
                  : RefreshIndicator(
                      onRefresh: onRefresh,
                      child: threads.isEmpty
                          ? ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: const [
                                SizedBox(height: 120),
                                Center(
                                    child: Text('No messages',
                                        style: TextStyle(color: Pal.soft))),
                              ],
                            )
                          : ListView.builder(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
                              itemCount: threads.length,
                              itemBuilder: (context, i) {
                                final t = threads[i];
                                final name = nameFor(t.address);
                                final title = name.isEmpty ? t.address : name;
                                final unread = t.unread > 0;
                                return Container(
                                  margin:
                                      const EdgeInsets.symmetric(vertical: 4),
                                  decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(18)),
                                  child: ListTile(
                                    onTap: () => onOpen(t),
                                    leading: GradientAvatar(
                                        name: name, seed: t.address),
                                    title: Text(title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            fontWeight: unread
                                                ? FontWeight.w800
                                                : FontWeight.w600)),
                                    subtitle: Text(
                                        '${t.mine ? 'You: ' : ''}${t.body}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            color:
                                                unread ? Pal.ink : Pal.soft)),
                                    trailing: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(whenLabel(t.date),
                                            style: const TextStyle(
                                                color: Pal.soft,
                                                fontSize: 12)),
                                        if (unread)
                                          Container(
                                            margin:
                                                const EdgeInsets.only(top: 4),
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 7, vertical: 2),
                                            decoration: BoxDecoration(
                                                gradient: Pal.brand,
                                                borderRadius:
                                                    BorderRadius.circular(10)),
                                            child: Text('${t.unread}',
                                                style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 11,
                                                    fontWeight:
                                                        FontWeight.w700)),
                                          ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
            ),
          ],
        ),
        Positioned(
          right: 20,
          bottom: 20,
          child: GestureDetector(
            onTap: onNew,
            child: Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: Pal.brand,
                boxShadow: [
                  BoxShadow(
                      color: Pal.magenta.withValues(alpha: 0.4),
                      blurRadius: 16,
                      offset: const Offset(0, 6)),
                ],
              ),
              child: const Icon(Icons.edit, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}

class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    required this.title,
    required this.address,
    required this.loader,
    required this.onSend,
    required this.onCall,
  });

  final String title;
  final String address;
  final Future<List<SmsMsg>> Function() loader;
  final Future<void> Function(String) onSend;
  final VoidCallback onCall;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final List<SmsMsg> _msgs = [];
  final _ctl = TextEditingController();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    widget.loader().then((m) {
      if (!mounted) return;
      setState(() {
        _msgs.addAll(m);
        _loading = false;
      });
    }).catchError((_) {
      if (mounted) setState(() => _loading = false);
    });
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _ctl.text.trim();
    if (text.isEmpty) return;
    _ctl.clear();
    setState(() =>
        _msgs.add(SmsMsg(body: text, date: DateTime.now(), mine: true)));
    try {
      await widget.onSend(text);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Message could not be sent. Check SMS permission.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: Text(widget.title,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
              tooltip: 'Call',
              onPressed: widget.onCall,
              icon: const Icon(Icons.call, color: Pal.green)),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.all(14),
                    itemCount: _msgs.length,
                    itemBuilder: (context, i) {
                      final m = _msgs[_msgs.length - 1 - i];
                      return Align(
                        alignment: m.mine
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 290),
                          margin: const EdgeInsets.symmetric(vertical: 3),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            gradient: m.mine ? Pal.brand : null,
                            color: m.mine ? null : Colors.white,
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(18),
                              topRight: const Radius.circular(18),
                              bottomLeft: Radius.circular(m.mine ? 18 : 4),
                              bottomRight: Radius.circular(m.mine ? 4 : 18),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(m.body,
                                  style: TextStyle(
                                      color:
                                          m.mine ? Colors.white : Pal.ink,
                                      fontSize: 15)),
                              const SizedBox(height: 3),
                              Text(whenLabel(m.date),
                                  style: TextStyle(
                                      fontSize: 10,
                                      color: m.mine
                                          ? Colors.white70
                                          : Pal.soft)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ctl,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.newline,
                      decoration: InputDecoration(
                        hintText: 'Text message',
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 10),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(26),
                            borderSide: BorderSide.none),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _send,
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: const BoxDecoration(
                          shape: BoxShape.circle, gradient: Pal.brand),
                      child: const Icon(Icons.send_rounded,
                          color: Colors.white, size: 22),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Settings
// ─────────────────────────────────────────────────────────────
class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.settings,
    required this.onRequestDialer,
    required this.onRequestCallerId,
    required this.onSilence,
    required this.onBlockedChanged,
    required this.onOpenAppSettings,
    required this.onPreviewIncoming,
    required this.onPreviewActive,
    required this.onRefresh,
  });

  final ValueNotifier<AppSettings> settings;
  final Future<void> Function() onRequestDialer;
  final Future<void> Function() onRequestCallerId;
  final ValueChanged<bool> onSilence;
  final ValueChanged<List<String>> onBlockedChanged;
  final VoidCallback onOpenAppSettings;
  final VoidCallback onPreviewIncoming;
  final VoidCallback onPreviewActive;
  final Future<void> Function() onRefresh;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with WidgetsBindingObserver {
  final _ctl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ctl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) widget.onRefresh();
  }

  Widget _card({required Widget child}) => Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(20)),
        child: child,
      );

  Widget _roleCard({
    required IconData icon,
    required List<Color> colors,
    required String title,
    required String body,
    required bool on,
    required VoidCallback onTap,
  }) {
    return _card(
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: colors)),
            child: Icon(icon, color: Colors.white),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 2),
                Text(body,
                    style: const TextStyle(color: Pal.soft, fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          on
              ? const Icon(Icons.check_circle, color: Pal.green)
              : FilledButton(
                  onPressed: onTap,
                  style: FilledButton.styleFrom(backgroundColor: Pal.violet),
                  child: const Text('Set'),
                ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Pal.bg,
        title: const Text('Settings',
            style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: ValueListenableBuilder<AppSettings>(
        valueListenable: widget.settings,
        builder: (context, s, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            _roleCard(
              icon: Icons.phone_in_talk,
              colors: const [Pal.green, Pal.teal],
              title: 'Default phone app',
              body: 'Calls open in Smart Dialer, full screen.',
              on: s.isDialer,
              onTap: () => widget.onRequestDialer(),
            ),
            _roleCard(
              icon: Icons.shield,
              colors: const [Pal.violet, Pal.indigo],
              title: 'Caller ID & spam app',
              body: 'Lets Smart Dialer silence or block callers.',
              on: s.isCallerId,
              onTap: () => widget.onRequestCallerId(),
            ),
            _card(
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Silence unknown callers',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text(
                    'Numbers not in your contacts ring silently. They still show in Recents.'),
                value: s.silenceUnknown,
                activeTrackColor: Pal.violet,
                onChanged: widget.onSilence,
              ),
            ),
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Blocked numbers',
                      style:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _ctl,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                              hintText: 'Add a number to block'),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle, color: Pal.violet),
                        onPressed: () {
                          final n = _ctl.text.trim();
                          if (n.isEmpty) return;
                          widget.onBlockedChanged([...s.blocked, n]);
                          _ctl.clear();
                        },
                      ),
                    ],
                  ),
                  if (s.blocked.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text('No blocked numbers',
                          style: TextStyle(color: Pal.soft)),
                    ),
                  for (final n in s.blocked)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      leading: const Icon(Icons.block, color: Pal.red),
                      title: Text(n),
                      trailing: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => widget.onBlockedChanged(
                            s.blocked.where((x) => x != n).toList()),
                      ),
                    ),
                ],
              ),
            ),
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Preview call screens',
                      style:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: widget.onPreviewIncoming,
                        icon: const Icon(Icons.call_received),
                        label: const Text('Incoming'),
                      ),
                      OutlinedButton.icon(
                        onPressed: widget.onPreviewActive,
                        icon: const Icon(Icons.call_made),
                        label: const Text('Outgoing'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            TextButton.icon(
              onPressed: widget.onOpenAppSettings,
              icon: const Icon(Icons.settings_applications),
              label: const Text('Open Android app permissions'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// In-call: backends
// ─────────────────────────────────────────────────────────────
class CallInfo {
  const CallInfo({
    this.state = 'idle',
    this.number = '',
    this.name = '',
    this.connectMs = 0,
    this.muted = false,
    this.speaker = false,
  });
  final String state; // idle, ringing, dialing, active, holding, ended
  final String number;
  final String name;
  final int connectMs;
  final bool muted;
  final bool speaker;

  CallInfo copyWith(
          {String? state, int? connectMs, bool? muted, bool? speaker}) =>
      CallInfo(
        state: state ?? this.state,
        number: number,
        name: name,
        connectMs: connectMs ?? this.connectMs,
        muted: muted ?? this.muted,
        speaker: speaker ?? this.speaker,
      );

  factory CallInfo.fromMap(Map<String, dynamic> m, CallInfo prev) {
    final s = (m['state'] as String?) ?? 'idle';
    if (s == 'none') {
      return prev.copyWith(
          state: prev.state == 'idle' ? 'idle' : 'ended',
          muted: false,
          speaker: false);
    }
    return CallInfo(
      state: s,
      number: (m['number'] as String?) ?? '',
      name: (m['name'] as String?) ?? '',
      connectMs: (m['connectTime'] as num?)?.toInt() ?? 0,
      muted: m['muted'] == true,
      speaker: m['speaker'] == true,
    );
  }
}

abstract class CallBackend {
  final ValueNotifier<CallInfo> info = ValueNotifier<CallInfo>(const CallInfo());
  void answer();
  void reject();
  void rejectWithMessage(String text);
  void hangup();
  void setMute(bool v);
  void setSpeaker(bool v);
  void setHold(bool v);
  void dtmf(String d);
  void closeUi();
}

/// Talks to SmartInCallService.kt (real calls, Android default phone app).
class NativeCallBackend extends CallBackend {
  static const _ch = MethodChannel('smart_dialer/call');

  NativeCallBackend() {
    _ch.setMethodCallHandler((c) async {
      if (c.method == 'state') {
        info.value = CallInfo.fromMap(
            Map<String, dynamic>.from(c.arguments as Map), info.value);
      }
      return null;
    });
    refresh();
  }

  Future<void> refresh() async {
    try {
      final r = await _ch.invokeMapMethod<String, dynamic>('getState');
      if (r != null) info.value = CallInfo.fromMap(r, info.value);
    } catch (_) {}
  }

  Future<void> _send(String m, [dynamic a]) async {
    try {
      await _ch.invokeMethod<void>(m, a);
    } catch (_) {}
  }

  @override
  void answer() => _send('answer');
  @override
  void reject() => _send('reject');
  @override
  void rejectWithMessage(String text) => _send('rejectWithMessage', text);
  @override
  void hangup() => _send('hangup');
  @override
  void setMute(bool v) => _send('mute', v);
  @override
  void setSpeaker(bool v) => _send('speaker', v);
  @override
  void setHold(bool v) => _send(v ? 'hold' : 'unhold');
  @override
  void dtmf(String d) => _send('dtmf', d);
  @override
  void closeUi() => _send('closeUi');
}

/// Fake call used for the preview (web page, or Settings > Preview).
class DemoCallBackend extends CallBackend {
  DemoCallBackend({
    required bool incoming,
    required String number,
    required String name,
    required this.onClose,
  }) {
    info.value = CallInfo(
        state: incoming ? 'ringing' : 'dialing', number: number, name: name);
    if (!incoming) Timer(const Duration(seconds: 2), _connect);
  }

  final VoidCallback onClose;

  void _connect() => info.value = info.value.copyWith(
      state: 'active', connectMs: DateTime.now().millisecondsSinceEpoch);
  void _end() => info.value = info.value.copyWith(state: 'ended');

  @override
  void answer() => _connect();
  @override
  void reject() => _end();
  @override
  void rejectWithMessage(String text) => _end();
  @override
  void hangup() => _end();
  @override
  void setMute(bool v) => info.value = info.value.copyWith(muted: v);
  @override
  void setSpeaker(bool v) => info.value = info.value.copyWith(speaker: v);
  @override
  void setHold(bool v) =>
      info.value = info.value.copyWith(state: v ? 'holding' : 'active');
  @override
  void dtmf(String d) {}
  @override
  void closeUi() => onClose();
}

// ─────────────────────────────────────────────────────────────
// In-call: full-screen UI
// ─────────────────────────────────────────────────────────────
class InCallApp extends StatefulWidget {
  const InCallApp({super.key});

  @override
  State<InCallApp> createState() => _InCallAppState();
}

class _InCallAppState extends State<InCallApp> {
  final NativeCallBackend _backend = NativeCallBackend();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true),
      home: InCallScreen(backend: _backend),
    );
  }
}

class InCallScreen extends StatefulWidget {
  const InCallScreen({super.key, required this.backend});
  final CallBackend backend;

  @override
  State<InCallScreen> createState() => _InCallScreenState();
}

class _InCallScreenState extends State<InCallScreen> {
  Timer? _tick;
  bool _pad = false;
  bool _closing = false;
  String _typed = '';

  static const _quick = [
    "Can't talk now, will call you back.",
    'I am in a meeting. Message me.',
    'Call you later.',
  ];

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    widget.backend.info.addListener(_onInfo);
  }

  @override
  void dispose() {
    widget.backend.info.removeListener(_onInfo);
    _tick?.cancel();
    super.dispose();
  }

  void _onInfo() {
    final s = widget.backend.info.value.state;
    if (s == 'ended' && !_closing) {
      _closing = true;
      Future<void>.delayed(const Duration(milliseconds: 1300), () {
        if (widget.backend.info.value.state == 'ended') {
          widget.backend.closeUi();
        }
        _closing = false;
      });
    }
    if (s == 'ringing' || s == 'dialing') {
      _pad = false;
      _typed = '';
    }
  }

  String _status(CallInfo i) {
    switch (i.state) {
      case 'ringing':
        return 'Incoming call';
      case 'dialing':
        return 'Calling...';
      case 'holding':
        return 'On hold';
      case 'ended':
        return 'Call ended';
      case 'active':
        if (i.connectMs > 0) {
          return fmtDuration(DateTime.now()
              .difference(DateTime.fromMillisecondsSinceEpoch(i.connectMs)));
        }
        return 'Connected';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: Pal.callBg),
        child: SafeArea(
          child: ValueListenableBuilder<CallInfo>(
            valueListenable: widget.backend.info,
            builder: (context, i, _) {
              final unknown = i.name.isEmpty;
              final title = unknown
                  ? (i.number.isEmpty ? 'Unknown caller' : i.number)
                  : i.name;
              return Column(
                children: [
                  const SizedBox(height: 28),
                  Text(_status(i),
                      style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 17,
                          letterSpacing: 0.4)),
                  if (unknown && i.state != 'idle')
                    Container(
                      margin: const EdgeInsets.only(top: 10),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                          color: Pal.orange.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(14)),
                      child: const Text('Unknown caller',
                          style: TextStyle(color: Colors.white, fontSize: 12)),
                    ),
                  Expanded(
                    child: _pad
                        ? _padView(i)
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: Pal.brand),
                                child: GradientAvatar(
                                    name: i.name,
                                    seed: i.number.isEmpty ? title : i.number,
                                    radius: 62),
                              ),
                              const SizedBox(height: 26),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 24),
                                child: Text(title,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 34,
                                        fontWeight: FontWeight.w700)),
                              ),
                              if (!unknown)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(i.number,
                                      style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 17)),
                                ),
                            ],
                          ),
                  ),
                  if (i.state == 'ringing') _ringingControls(),
                  if (i.state != 'ringing' && i.state != 'idle')
                    _activeControls(i),
                  const SizedBox(height: 30),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _padView(CallInfo i) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          height: 44,
          child: Text(_typed,
              style: const TextStyle(color: Colors.white, fontSize: 30)),
        ),
        DialPad(
          dark: true,
          size: 66,
          onKey: (d) {
            widget.backend.dtmf(d);
            setState(() => _typed += d);
          },
        ),
      ],
    );
  }

  Widget _ringingControls() {
    return Column(
      children: [
        SizedBox(
          height: 42,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              for (final q in _quick)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    backgroundColor: Colors.white.withValues(alpha: 0.16),
                    side: BorderSide.none,
                    label: Text(q,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 13)),
                    onPressed: () => widget.backend.rejectWithMessage(q),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _RoundBtn(
                icon: Icons.call_end,
                label: 'Decline',
                color: Pal.red,
                size: 76,
                onTap: widget.backend.reject),
            _RoundBtn(
                icon: Icons.call,
                label: 'Answer',
                color: Pal.green,
                size: 76,
                pulse: true,
                onTap: widget.backend.answer),
          ],
        ),
      ],
    );
  }

  Widget _activeControls(CallInfo i) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _RoundBtn(
                icon: i.muted ? Icons.mic_off : Icons.mic,
                label: 'Mute',
                active: i.muted,
                onTap: () => widget.backend.setMute(!i.muted)),
            _RoundBtn(
                icon: Icons.dialpad,
                label: 'Keypad',
                active: _pad,
                onTap: () => setState(() => _pad = !_pad)),
            _RoundBtn(
                icon: Icons.volume_up,
                label: 'Speaker',
                active: i.speaker,
                onTap: () => widget.backend.setSpeaker(!i.speaker)),
            _RoundBtn(
                icon: Icons.pause,
                label: 'Hold',
                active: i.state == 'holding',
                onTap: () => widget.backend.setHold(i.state != 'holding')),
          ],
        ),
        const SizedBox(height: 28),
        _RoundBtn(
            icon: Icons.call_end,
            label: 'End',
            color: Pal.red,
            size: 76,
            onTap: widget.backend.hangup),
      ],
    );
  }
}

class _RoundBtn extends StatelessWidget {
  const _RoundBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
    this.active = false,
    this.size = 64,
    this.pulse = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  final bool active;
  final double size;
  final bool pulse;

  @override
  Widget build(BuildContext context) {
    final bg = color ?? (active ? Colors.white : Colors.white.withValues(alpha: 0.16));
    final fg = color != null ? Colors.white : (active ? Pal.ink : Colors.white);
    final circle = Material(
      color: bg,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, color: fg, size: size * 0.42),
        ),
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        pulse ? _Pulse(color: color ?? Pal.green, child: circle) : circle,
        const SizedBox(height: 8),
        Text(label,
            style: const TextStyle(color: Colors.white70, fontSize: 13)),
      ],
    );
  }
}

class _Pulse extends StatefulWidget {
  const _Pulse({required this.child, required this.color});
  final Widget child;
  final Color color;

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1500));

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
        final spread = 22.0 * t;
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
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: widget.color.withValues(alpha: 0.6 * (1 - t)),
                        width: 3),
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
