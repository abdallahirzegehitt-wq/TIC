import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

const _kPrimary = Color(0xFF2962FF);
const _kCard = Color(0xFF1E2329);
const _kInitialBalance = 10000.0;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await TradeStore.I.load();
  runApp(const TicApp());
}

enum TradeType { buy, sell }

class Trade {
  final String id;
  final String asset;
  final TradeType type;
  final double entryPrice;
  final double exitPrice;
  final double lots;
  final double pnl;
  final String notes;
  final String mood;
  final DateTime date;

  const Trade({
    required this.id,
    required this.asset,
    required this.type,
    required this.entryPrice,
    required this.exitPrice,
    required this.lots,
    required this.pnl,
    this.notes = '',
    this.mood = 'عادي',
    required this.date,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'asset': asset,
        'type': type.name,
        'entry': entryPrice,
        'exit': exitPrice,
        'lots': lots,
        'pnl': pnl,
        'notes': notes,
        'mood': mood,
        'date': date.toIso8601String(),
      };

  factory Trade.fromJson(Map<String, dynamic> j) => Trade(
        id: j['id'] as String,
        asset: j['asset'] as String,
        type: TradeType.values.byName(j['type'] as String),
        entryPrice: (j['entry'] as num).toDouble(),
        exitPrice: (j['exit'] as num).toDouble(),
        lots: (j['lots'] as num).toDouble(),
        pnl: (j['pnl'] as num).toDouble(),
        notes: (j['notes'] as String?) ?? '',
        mood: (j['mood'] as String?) ?? 'عادي',
        date: DateTime.parse(j['date'] as String),
      );
}

class Signal {
  final String pair;
  final bool isBuy;
  final String entry, sl, tp;
  final bool halal;
  const Signal({required this.pair, required this.isBuy, required this.entry, required this.sl, required this.tp, required this.halal});
}

class Trader {
  final String id, name, focus, winRate, monthly, risk;
  const Trader(this.id, this.name, this.focus, this.winRate, this.monthly, this.risk);
}

class Plan {
  final String id, name, price;
  final List<String> features;
  const Plan(this.id, this.name, this.price, this.features);
}

const _pipValue = <String, double>{
  'XAUUSD': 100.0,
  'EURUSD': 100000.0,
  'GBPUSD': 100000.0,
  'US30': 10.0,
  'BTCUSD': 1.0,
};

double calcPnl(String asset, TradeType type, double entry, double exit, double lots) {
  final dir = type == TradeType.buy ? 1 : -1;
  return (exit - entry) * dir * (_pipValue[asset.toUpperCase()] ?? 1.0) * lots;
}

class TradeStore extends ChangeNotifier {
  static final TradeStore I = TradeStore._();
  TradeStore._();

  final List<Trade> trades = [];
  bool halal = false;
  Set<String> followed = {};
  String plan = 'free';

  double get balance => _kInitialBalance + trades.fold(0.0, (s, t) => s + t.pnl);

  List<FlSpot> get spots {
    final out = <FlSpot>[const FlSpot(0, _kInitialBalance)];
    var run = _kInitialBalance;
    final chrono = trades.reversed.toList();
    for (var i = 0; i < chrono.length; i++) {
      run += chrono[i].pnl;
      out.add(FlSpot((i + 1).toDouble(), run));
    }
    return out;
  }

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString('trades');
      if (raw != null) {
        final list = jsonDecode(raw) as List;
        trades
          ..clear()
          ..addAll(list.map((e) => Trade.fromJson(e as Map<String, dynamic>)));
      }
      halal = p.getBool('halal') ?? false;
      followed = (p.getStringList('followed') ?? []).toSet();
      plan = p.getString('plan') ?? 'free';
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('trades', jsonEncode(trades.map((t) => t.toJson()).toList()));
      await p.setBool('halal', halal);
      await p.setStringList('followed', followed.toList());
      await p.setString('plan', plan);
    } catch (_) {}
  }

  void _changed() {
    notifyListeners();
    _save();
  }

  void addTrade(Trade t) {
    trades.insert(0, t);
    _changed();
  }

  void removeTrade(String id) {
    trades.removeWhere((t) => t.id == id);
    _changed();
  }

  void clearTrades() {
    trades.clear();
    _changed();
  }

  void setHalal(bool v) {
    halal = v;
    _changed();
  }

  void toggleFollow(String id) {
    followed.contains(id) ? followed.remove(id) : followed.add(id);
    _changed();
  }

  void setPlan(String id) {
    plan = id;
    _changed();
  }

  void seedDemo() {
    const rows = <List<Object>>[
      ['XAUUSD', TradeType.buy, 2340.0, 2352.0, 0.1, 'متأكد', 0],
      ['EURUSD', TradeType.sell, 1.0900, 1.0860, 0.2, 'عادي', 1],
      ['US30', TradeType.buy, 39200.0, 39150.0, 0.5, 'مستعجل', 2],
      ['BTCUSD', TradeType.buy, 41000.0, 41800.0, 0.1, 'متحمس', 3],
      ['XAUUSD', TradeType.sell, 2360.0, 2366.0, 0.1, 'خائف', 4],
      ['GBPUSD', TradeType.buy, 1.2650, 1.2700, 0.2, 'متأكد', 5],
      ['EURUSD', TradeType.buy, 1.0850, 1.0820, 0.3, 'مستعجل', 6],
      ['XAUUSD', TradeType.buy, 2330.0, 2345.0, 0.1, 'عادي', 8],
      ['US30', TradeType.sell, 39300.0, 39220.0, 0.3, 'عادي', 9],
      ['BTCUSD', TradeType.sell, 42500.0, 42900.0, 0.1, 'متحمس', 11],
    ];
    final now = DateTime.now();
    final demo = rows.map((r) {
      final asset = r[0] as String;
      final type = r[1] as TradeType;
      final entry = r[2] as double;
      final exit = r[3] as double;
      final lots = r[4] as double;
      return Trade(
        id: const Uuid().v4(),
        asset: asset,
        type: type,
        entryPrice: entry,
        exitPrice: exit,
        lots: lots,
        pnl: calcPnl(asset, type, entry, exit, lots),
        mood: r[5] as String,
        notes: 'صفقة تجريبية',
        date: now.subtract(Duration(days: r[6] as int)),
      );
    }).toList();
    trades.addAll(demo);
    trades.sort((a, b) => b.date.compareTo(a.date));
    _changed();
  }
}

class TicApp extends StatelessWidget {
  const TicApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TIC',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0B0E11),
        cardColor: _kCard,
        primaryColor: _kPrimary,
        useMaterial3: true,
      ),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ar'), Locale('en')],
      locale: const Locale('ar'),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: TradeStore.I,
      builder: (context, _) {
        final screens = <Widget>[
          DashboardScreen(onGoTo: (i) => setState(() => _currentIndex = i)),
          SignalsScreen(isHalalOnly: TradeStore.I.halal),
          const JournalScreen(),
          const LiveMarketScreen(),
          const MoreScreen(),
        ];
        return Scaffold(
          body: IndexedStack(index: _currentIndex, children: screens),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: (i) => setState(() => _currentIndex = i),
            backgroundColor: _kCard,
            indicatorColor: const Color(0x332962FF),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'الرئيسية'),
              NavigationDestination(icon: Icon(Icons.trending_up_outlined), selectedIcon: Icon(Icons.trending_up), label: 'الإشارات'),
              NavigationDestination(icon: Icon(Icons.book_outlined), selectedIcon: Icon(Icons.book), label: 'المفكرة'),
              NavigationDestination(icon: Icon(Icons.show_chart_outlined), selectedIcon: Icon(Icons.show_chart), label: 'الأسواق'),
              NavigationDestination(icon: Icon(Icons.more_horiz), selectedIcon: Icon(Icons.menu), label: 'المزيد'),
            ],
          ),
        );
      },
    );
  }
}

void _push(BuildContext context, Widget screen) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

class DashboardScreen extends StatelessWidget {
  final ValueChanged<int> onGoTo;
  const DashboardScreen({super.key, required this.onGoTo});

  @override
  Widget build(BuildContext context) {
    final store = TradeStore.I;
    final pnl = store.balance - _kInitialBalance;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [_kPrimary, Color(0xFF00B0FF)]),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('تداول بذكاء.', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                  Text('ليس بإرهاق.', style: TextStyle(color: Colors.white70, fontSize: 22, fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  Text('إشارات AI • مستشار ذكي • مفكرة • دوري أسبوعي', style: TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Card(
              color: Theme.of(context).cardColor,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('الرصيد', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      Text('\$${store.balance.toStringAsFixed(2)}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    ]),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      const Text('الربح/الخسارة', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      Text('${pnl >= 0 ? '+' : ''}${pnl.toStringAsFixed(2)}',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: pnl >= 0 ? Colors.green : Colors.red)),
                    ]),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('أدواتك السريعة', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              children: [
                _quickCard(context, 'المستشار الذكي', Icons.smart_toy, () => _push(context, const AiAdvisorScreen())),
                _quickCard(context, 'مراجعة AI لصفقاتك', Icons.auto_awesome, () => _push(context, const AiReviewScreen())),
                _quickCard(context, 'نسخ التداول', Icons.copy_all, () => _push(context, const CopyTradingScreen())),
                _quickCard(context, 'الدوري الأسبوعي', Icons.emoji_events, () => _push(context, const LeagueScreen())),
                _quickCard(context, 'الباقات', Icons.workspace_premium, () => _push(context, const PlansScreen())),
                _quickCard(context, 'الأكاديمية', Icons.school, () => _push(context, const AcademyScreen())),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickCard(BuildContext context, String title, IconData icon, VoidCallback onTap) {
    return Card(
      color: Theme.of(context).cardColor,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 32, color: _kPrimary),
              const SizedBox(height: 8),
              Text(title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }
}

class SignalsScreen extends StatelessWidget {
  final bool isHalalOnly;
  const SignalsScreen({super.key, this.isHalalOnly = false});

  static const _signals = <Signal>[
    Signal(pair: 'XAUUSD', isBuy: true, entry: '2350.50', sl: '2345.00', tp: '2365.00', halal: true),
    Signal(pair: 'EURUSD', isBuy: false, entry: '1.0850', sl: '1.0880', tp: '1.0780', halal: true),
    Signal(pair: 'BTCUSD', isBuy: true, entry: '42000', sl: '41500', tp: '43500', halal: false),
    Signal(pair: 'US30', isBuy: true, entry: '39100', sl: '38950', tp: '39400', halal: true),
    Signal(pair: 'GBPUSD', isBuy: true, entry: '1.2700', sl: '1.2660', tp: '1.2790', halal: true),
  ];

  @override
  Widget build(BuildContext context) {
    final list = isHalalOnly ? _signals.where((s) => s.halal).toList() : _signals;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(children: [
            const Text('إشارات اليوم', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const Spacer(),
            if (isHalalOnly) const Chip(label: Text('حلال فقط'), avatar: Icon(Icons.check, color: Colors.green, size: 16)),
          ]),
          const Text('إشارات تجريبية للتعليم وليست توصية مالية', style: TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 12),
          ...list.map((s) => Card(
                color: Theme.of(context).cardColor,
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [
                    Row(children: [
                      Text(s.pair, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: s.isBuy ? Colors.green : Colors.red, borderRadius: BorderRadius.circular(6)),
                        child: Text(s.isBuy ? 'شراء' : 'بيع', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                      const Spacer(),
                      Text(s.halal ? 'بدون سواب ✓' : 'يحتوي سواب', style: TextStyle(fontSize: 11, color: s.halal ? Colors.green : Colors.orange)),
                    ]),
                    const SizedBox(height: 10),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      _lvl('دخول', s.entry),
                      _lvl('وقف', s.sl),
                      _lvl('هدف', s.tp),
                    ]),
                  ]),
                ),
              )),
        ],
      ),
    );
  }

  Widget _lvl(String l, String v) => Column(children: [
        Text(l, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        Text(v, style: const TextStyle(fontWeight: FontWeight.bold)),
      ]);
}

class JournalScreen extends StatefulWidget {
  const JournalScreen({super.key});

  @override
  State<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends State<JournalScreen> {
  final _formKey = GlobalKey<FormState>();
  final _assetC = TextEditingController();
  final _entryC = TextEditingController();
  final _exitC = TextEditingController();
  final _lotsC = TextEditingController(text: '0.1');
  final _notesC = TextEditingController();
  TradeType _type = TradeType.buy;
  String _mood = 'عادي';

  double? _parse(String s) => double.tryParse(s.trim().replaceAll(',', '.'));
  String? _numValidator(String? v) {
    if (v == null || v.trim().isEmpty) return 'مطلوب';
    return _parse(v) == null ? 'رقم غير صالح' : null;
  }

  String? _lotsValidator(String? v) {
    final n = _parse(v ?? '');
    return (n == null || n <= 0) ? 'رقم > 0' : null;
  }

  void _addTrade() {
    if (!_formKey.currentState!.validate()) return;
    final asset = _assetC.text.trim().toUpperCase();
    final entry = _parse(_entryC.text)!;
    final exit = _parse(_exitC.text)!;
    final lots = _parse(_lotsC.text)!;
    TradeStore.I.addTrade(Trade(
      id: const Uuid().v4(),
      asset: asset,
      type: _type,
      entryPrice: entry,
      exitPrice: exit,
      lots: lots,
      pnl: calcPnl(asset, _type, entry, exit, lots),
      notes: _notesC.text.trim(),
      mood: _mood,
      date: DateTime.now(),
    ));
    _entryC.clear();
    _exitC.clear();
    _assetC.clear();
    _notesC.clear();
  }

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('مسح كل الصفقات؟'),
        content: const Text('لا يمكن التراجع عن هذا الإجراء.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('مسح')),
        ],
      ),
    );
    if (ok == true) TradeStore.I.clearTrades();
  }

  @override
  void dispose() {
    _assetC.dispose();
    _entryC.dispose();
    _exitC.dispose();
    _lotsC.dispose();
    _notesC.dispose();
    super.dispose();
  }

  String _fmtDate(DateTime d) =>
      '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: TradeStore.I,
      builder: (context, _) {
        final store = TradeStore.I;
        final trades = store.trades;
        final balance = store.balance;
        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                color: Theme.of(context).cardColor,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      const Text('منحنى رأس المال', style: TextStyle(fontWeight: FontWeight.bold)),
                      Text('\$${balance.toStringAsFixed(2)}',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: balance >= _kInitialBalance ? Colors.green : Colors.red)),
                    ]),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 140,
                      child: LineChart(LineChartData(
                        gridData: const FlGridData(show: false),
                        titlesData: const FlTitlesData(show: false),
                        borderData: FlBorderData(show: false),
                        lineBarsData: [
                          LineChartBarData(
                            spots: store.spots,
                            isCurved: true,
                            color: _kPrimary,
                            barWidth: 3,
                            dotData: const FlDotData(show: false),
                          ),
                        ],
                      )),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                color: Theme.of(context).cardColor,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Form(
                    key: _formKey,
                    child: Column(children: [
                      TextFormField(
                        controller: _assetC,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(labelText: 'الأصل (XAUUSD)'),
                        validator: (v) => v == null || v.trim().isEmpty ? 'مطلوب' : null,
                      ),
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(child: TextFormField(controller: _entryC, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'دخول'), validator: _numValidator)),
                        const SizedBox(width: 8),
                        Expanded(child: TextFormField(controller: _exitC, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'خروج'), validator: _numValidator)),
                        const SizedBox(width: 8),
                        Expanded(child: TextFormField(controller: _lotsC, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'لوت'), validator: _lotsValidator)),
                      ]),
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(
                          child: DropdownButtonFormField<TradeType>(
                            value: _type,
                            items: const [
                              DropdownMenuItem(value: TradeType.buy, child: Text('شراء')),
                              DropdownMenuItem(value: TradeType.sell, child: Text('بيع')),
                            ],
                            onChanged: (v) => setState(() => _type = v ?? _type),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _mood,
                            items: const ['عادي', 'متحمس', 'خائف', 'متأكد', 'مستعجل']
                                .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                                .toList(),
                            onChanged: (v) => setState(() => _mood = v ?? _mood),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 10),
                      TextFormField(controller: _notesC, maxLines: 2, decoration: const InputDecoration(labelText: 'ملاحظات (اختياري)')),
                      const SizedBox(height: 12),
                      SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _addTrade, child: const Text('حفظ الصفقة'))),
                    ]),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(children: [
                const Text('سجل الصفقات', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const Spacer(),
                TextButton.icon(onPressed: store.seedDemo, icon: const Icon(Icons.science_outlined, size: 18), label: const Text('بيانات تجريبية')),
                if (trades.isNotEmpty) IconButton(onPressed: _confirmClear, icon: const Icon(Icons.delete_sweep_outlined)),
              ]),
              const SizedBox(height: 8),
              if (trades.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('لا توجد صفقات بعد — أضف صفقة أو حمّل بيانات تجريبية', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey))),
                )
              else
                ...trades.map((t) => Card(
                      color: Theme.of(context).cardColor,
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: Icon(t.type == TradeType.buy ? Icons.arrow_upward : Icons.arrow_downward, color: t.type == TradeType.buy ? Colors.green : Colors.red),
                        title: Text('${t.asset} • ${t.lots} لوت'),
                        subtitle: Text('${t.entryPrice} ← ${t.exitPrice} • ${t.mood}\n${_fmtDate(t.date)}${t.notes.isEmpty ? '' : '\n${t.notes}'}'),
                        isThreeLine: true,
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          Text('${t.pnl >= 0 ? '+' : ''}${t.pnl.toStringAsFixed(2)}',
                              style: TextStyle(fontWeight: FontWeight.bold, color: t.pnl >= 0 ? Colors.green : Colors.red)),
                          IconButton(icon: const Icon(Icons.delete_outline, size: 20), onPressed: () => TradeStore.I.removeTrade(t.id)),
                        ]),
                      ),
                    )),
            ],
          ),
        );
      },
    );
  }
}
class LiveMarketScreen extends StatefulWidget {
  const LiveMarketScreen({super.key});

  @override
  State<LiveMarketScreen> createState() => _LiveMarketScreenState();
}

class _LiveMarketScreenState extends State<LiveMarketScreen> {
  static const _open = <String, double>{'XAUUSD': 2350.5, 'EURUSD': 1.0850, 'GBPUSD': 1.2700, 'US30': 39100.0, 'BTCUSD': 42000.0};
  static const _decimals = <String, int>{'XAUUSD': 2, 'EURUSD': 4, 'GBPUSD': 4, 'US30': 1, 'BTCUSD': 1};
  late final Map<String, double> _price = Map.of(_open);
  final _rand = Random();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted) return;
      setState(() {
        for (final k in _price.keys.toList()) {
          _price[k] = _price[k]! * (1 + (_rand.nextDouble() - 0.5) * 0.0006);
        }
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('الأسواق', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const Text('أسعار محاكاة تتحدث كل ثانيتين — اربطها بمزوّد أسعار حقيقي لاحقاً', style: TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 12),
          ..._price.entries.map((e) {
            final pct = (e.value / _open[e.key]! - 1) * 100;
            final up = pct >= 0;
            return Card(
              color: Theme.of(context).cardColor,
              child: ListTile(
                title: Text(e.key, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(e.value.toStringAsFixed(_decimals[e.key]!)),
                trailing: Text('${up ? '+' : ''}${pct.toStringAsFixed(2)}%', style: TextStyle(color: up ? Colors.green : Colors.red, fontWeight: FontWeight.bold)),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = TradeStore.I;
    Widget tile(String title, IconData icon, Widget screen) => Card(
          color: Theme.of(context).cardColor,
          child: ListTile(leading: Icon(icon, color: _kPrimary), title: Text(title), trailing: const Icon(Icons.chevron_left), onTap: () => _push(context, screen)),
        );
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('المزيد', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Card(
            color: Theme.of(context).cardColor,
            child: SwitchListTile(
              title: const Text('إشارات الحلال فقط'),
              subtitle: const Text('إخفاء الأصول التي تحتوي سواب'),
              value: store.halal,
              onChanged: store.setHalal,
            ),
          ),
          tile('المستشار الذكي', Icons.smart_toy, const AiAdvisorScreen()),
          tile('مراجعة AI لصفقاتك', Icons.auto_awesome, const AiReviewScreen()),
          tile('نسخ التداول', Icons.copy_all, const CopyTradingScreen()),
          tile('الدوري الأسبوعي', Icons.emoji_events, const LeagueScreen()),
          tile('الأكاديمية', Icons.school, const AcademyScreen()),
          tile('الباقات', Icons.workspace_premium, const PlansScreen()),
        ],
      ),
    );
  }
}

class _Msg {
  final String text;
  final bool mine;
  const _Msg(this.text, this.mine);
}

class AiAdvisorScreen extends StatefulWidget {
  const AiAdvisorScreen({super.key});

  @override
  State<AiAdvisorScreen> createState() => _AiAdvisorScreenState();
}

class _AiAdvisorScreenState extends State<AiAdvisorScreen> {
  final _c = TextEditingController();
  final _scroll = ScrollController();
  final List<_Msg> _msgs = [
    const _Msg('أهلاً! أنا مستشار تجريبي أجيب بقواعد محلية. اسألني عن المخاطرة، وقف الخسارة، الذهب، الحلال، أو الجانب النفسي. المحتوى تعليمي وليس نصيحة مالية.', false),
  ];

  String _reply(String q) {
    bool has(List<String> k) => k.any(q.contains);
    if (has(['سواب', 'حلال', 'اسلام', 'إسلام'])) {
      return 'الحسابات الإسلامية تُعفي من السواب لكن قد تفرض رسوماً بديلة، فتأكد من شروط وسيطك. فعّل «حلال فقط» من تبويب المزيد.';
    }
    if (has(['ذهب', 'xau'])) {
      return 'الذهب شديد التذبذب: استخدم لوتاً صغيراً ووقفاً واضحاً، وتجنب الدخول لحظة صدور الأخبار الكبرى.';
    }
    if (has(['مخاطر', 'لوت', 'حجم', 'رأس'])) {
      return 'قاعدة شائعة: لا تخاطر بأكثر من 1–2% من رأس المال في الصفقة. حجم اللوت = (الرصيد × نسبة المخاطرة) ÷ (مسافة الوقف × قيمة النقطة).';
    }
    if (has(['وقف', 'ستوب', 'stop'])) {
      return 'ضع وقف الخسارة عند مستوى يُبطل فكرة الصفقة (خلف قمة/قاع منطقي) ولا تحرّكه بعيداً بعد الدخول. اجعل الهدف على الأقل ضعف الوقف.';
    }
    if (has(['خوف', 'خائف', 'طمع', 'انتقام', 'نفس', 'توتر'])) {
      return 'بعد خسارتين متتاليتين خذ استراحة ولا تضاعف اللوت للتعويض. سجّل حالتك المزاجية في المفكرة لتكتشف متى تسوء قراراتك.';
    }
    if (has(['مرحبا', 'سلام', 'اهلا', 'أهلا'])) return 'أهلاً بك! كيف أساعدك في تداولك اليوم؟';
    return 'سؤال جيد. جرّب أن تسأل عن: المخاطرة وحجم اللوت، وقف الخسارة، الذهب، الحلال، أو الجانب النفسي.';
  }

  void _send() {
    final t = _c.text.trim();
    if (t.isEmpty) return;
    setState(() {
      _msgs.add(_Msg(t, true));
      _msgs.add(_Msg(_reply(t), false));
    });
    _c.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    });
  }

  @override
  void dispose() {
    _c.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('المستشار الذكي')),
      body: Column(children: [
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.all(12),
            itemCount: _msgs.length,
            itemBuilder: (_, i) {
              final m = _msgs[i];
              return Align(
                alignment: m.mine ? AlignmentDirectional.centerStart : AlignmentDirectional.centerEnd,
                child: Container(
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: m.mine ? _kPrimary : _kCard, borderRadius: BorderRadius.circular(12)),
                  child: Text(m.text),
                ),
              );
            },
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(children: [
              Expanded(child: TextField(controller: _c, onSubmitted: (_) => _send(), decoration: const InputDecoration(hintText: 'اكتب سؤالك...', border: OutlineInputBorder()))),
              const SizedBox(width: 8),
              IconButton.filled(onPressed: _send, icon: const Icon(Icons.send)),
            ]),
          ),
        ),
      ]),
    );
  }
}

class AiReviewScreen extends StatelessWidget {
  const AiReviewScreen({super.key});

  Widget _stat(String l, String v, [Color? c]) => Column(children: [
        Text(l, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        const SizedBox(height: 4),
        Text(v, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: c)),
      ]);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('مراجعة AI لصفقاتك')),
      body: ListenableBuilder(
        listenable: TradeStore.I,
        builder: (context, _) {
          final ts = TradeStore.I.trades;
          if (ts.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('لا توجد صفقات للتحليل.\nأضف صفقات أو حمّل بيانات تجريبية من المفكرة.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
              ),
            );
          }
          final wins = ts.where((t) => t.pnl > 0).toList();
          final losses = ts.where((t) => t.pnl < 0).toList();
          final total = ts.fold(0.0, (s, t) => s + t.pnl);
          final grossWin = wins.fold(0.0, (s, t) => s + t.pnl);
          final grossLoss = losses.fold(0.0, (s, t) => s + t.pnl.abs());
          final winRate = wins.length / ts.length * 100;
          final avgWin = wins.isEmpty ? 0.0 : grossWin / wins.length;
          final avgLoss = losses.isEmpty ? 0.0 : grossLoss / losses.length;
          final pf = grossLoss == 0 ? null : grossWin / grossLoss;

          final byMood = <String, List<double>>{};
          final byAsset = <String, double>{};
          for (final t in ts) {
            byMood.putIfAbsent(t.mood, () => []).add(t.pnl);
            byAsset[t.asset] = (byAsset[t.asset] ?? 0) + t.pnl;
          }
          final moodAvg = byMood.map((k, v) => MapEntry(k, v.fold(0.0, (a, b) => a + b) / v.length));
          final moods = moodAvg.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
          final assets = byAsset.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

          final tips = <String>[];
          if (ts.length < 10) tips.add('عدد الصفقات (${ts.length}) قليل؛ النتائج مؤشر أولي وليست قاعدة.');
          if (avgLoss > 0 && avgWin / avgLoss < 1) tips.add('متوسط الخسارة أكبر من متوسط الربح؛ اقترب بالوقف أو ابعد الهدف لتحسين العائد/المخاطرة.');
          if (winRate < 40) tips.add('نسبة الربح منخفضة؛ راجع شروط الدخول وقلّل عدد الصفقات.');
          if (moods.length > 1 && moods.last.value < 0) tips.add('أسوأ حالاتك أداءً: «${moods.last.key}» (متوسط ${moods.last.value.toStringAsFixed(1)}). تجنب التداول في هذه الحالة.');
          if (moods.isNotEmpty && moods.first.value > 0) tips.add('أفضل حالاتك أداءً: «${moods.first.key}» (متوسط +${moods.first.value.toStringAsFixed(1)}).');
          if (tips.isEmpty) tips.add('أداؤك متوازن حتى الآن؛ حافظ على الالتزام بخطتك.');

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                color: Theme.of(context).cardColor,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Wrap(
                    alignment: WrapAlignment.spaceAround,
                    runSpacing: 16,
                    spacing: 24,
                    children: [
                      _stat('الصفقات', '${ts.length}'),
                      _stat('نسبة الربح', '${winRate.toStringAsFixed(0)}%'),
                      _stat('صافي النتيجة', '${total >= 0 ? '+' : ''}${total.toStringAsFixed(1)}', total >= 0 ? Colors.green : Colors.red),
                      _stat('متوسط الربح', avgWin.toStringAsFixed(1), Colors.green),
                      _stat('متوسط الخسارة', avgLoss.toStringAsFixed(1), Colors.red),
                      _stat('عامل الربح', pf == null ? '∞' : pf.toStringAsFixed(2)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                color: Theme.of(context).cardColor,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('الأداء حسب الحالة المزاجية', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    ...moods.map((m) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                            Text('${m.key} (${byMood[m.key]!.length})'),
                            Text('${m.value >= 0 ? '+' : ''}${m.value.toStringAsFixed(1)}', style: TextStyle(color: m.value >= 0 ? Colors.green : Colors.red, fontWeight: FontWeight.bold)),
                          ]),
                        )),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                color: Theme.of(context).cardColor,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('الأداء حسب الأصل', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    ...assets.map((a) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                            Text(a.key),
                            Text('${a.value >= 0 ? '+' : ''}${a.value.toStringAsFixed(1)}', style: TextStyle(color: a.value >= 0 ? Colors.green : Colors.red, fontWeight: FontWeight.bold)),
                          ]),
                        )),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                color: Theme.of(context).cardColor,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Row(children: [Icon(Icons.lightbulb_outline, color: Colors.amber, size: 20), SizedBox(width: 8), Text('ملاحظات', style: TextStyle(fontWeight: FontWeight.bold))]),
                    const SizedBox(height: 8),
                    ...tips.map((t) => Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Text('• $t'))),
                  ]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class CopyTradingScreen extends StatelessWidget {
  const CopyTradingScreen({super.key});

  static const _traders = <Trader>[
    Trader('t1', 'أبو فهد', 'XAUUSD', '72%', '+8.4%', 'متوسط'),
    Trader('t2', 'سارة FX', 'EURUSD / GBPUSD', '65%', '+5.1%', 'منخفض'),
    Trader('t3', 'خالد المضارب', 'US30', '58%', '+11.9%', 'مرتفع'),
    Trader('t4', 'ليلى', 'XAUUSD / EURUSD', '69%', '+6.7%', 'منخفض'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('نسخ التداول')),
      body: ListenableBuilder(
        listenable: TradeStore.I,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('متداولون تجريبيون — لا يتم تنفيذ أي صفقات فعلية', style: TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 12),
            ..._traders.map((t) {
              final following = TradeStore.I.followed.contains(t.id);
              return Card(
                color: Theme.of(context).cardColor,
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const CircleAvatar(backgroundColor: _kPrimary, child: Icon(Icons.person, color: Colors.white)),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(t.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        Text(t.focus, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                      ])),
                      following
                          ? OutlinedButton(onPressed: () => TradeStore.I.toggleFollow(t.id), child: const Text('إلغاء'))
                          : FilledButton(onPressed: () => TradeStore.I.toggleFollow(t.id), child: const Text('نسخ')),
                    ]),
                    const SizedBox(height: 12),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                      Column(children: [const Text('نسبة الربح', style: TextStyle(color: Colors.grey, fontSize: 11)), Text(t.winRate, style: const TextStyle(fontWeight: FontWeight.bold))]),
                      Column(children: [const Text('شهرياً', style: TextStyle(color: Colors.grey, fontSize: 11)), Text(t.monthly, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green))]),
                      Column(children: [const Text('المخاطرة', style: TextStyle(color: Colors.grey, fontSize: 11)), Text(t.risk, style: const TextStyle(fontWeight: FontWeight.bold))]),
                    ]),
                  ]),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class LeagueScreen extends StatelessWidget {
  const LeagueScreen({super.key});

  static const _others = <MapEntry<String, double>>[
    MapEntry('أحمد', 4.8),
    MapEntry('سارة', 3.9),
    MapEntry('خالد', 2.7),
    MapEntry('ليلى', 1.4),
    MapEntry('عمر', -0.6),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الدوري الأسبوعي')),
      body: ListenableBuilder(
        listenable: TradeStore.I,
        builder: (context, _) {
          final weekAgo = DateTime.now().subtract(const Duration(days: 7));
          final weekPnl = TradeStore.I.trades.where((t) => t.date.isAfter(weekAgo)).fold(0.0, (s, t) => s + t.pnl);
          final myPct = weekPnl / _kInitialBalance * 100;
          final rows = [..._others, MapEntry('أنت', myPct)]..sort((a, b) => b.value.compareTo(a.value));
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text('الترتيب حسب عائد آخر 7 أيام (بيانات الآخرين تجريبية)', style: TextStyle(color: Colors.grey, fontSize: 12)),
              const SizedBox(height: 12),
              for (var i = 0; i < rows.length; i++)
                Card(
                  color: rows[i].key == 'أنت' ? const Color(0x332962FF) : Theme.of(context).cardColor,
                  child: ListTile(
                    leading: i < 3
                        ? Icon(Icons.emoji_events, color: [Colors.amber, Colors.grey, Colors.brown][i])
                        : CircleAvatar(radius: 14, backgroundColor: _kCard, child: Text('${i + 1}', style: const TextStyle(fontSize: 12))),
                    title: Text(rows[i].key, style: TextStyle(fontWeight: rows[i].key == 'أنت' ? FontWeight.bold : FontWeight.normal)),
                    trailing: Text('${rows[i].value >= 0 ? '+' : ''}${rows[i].value.toStringAsFixed(2)}%',
                        style: TextStyle(fontWeight: FontWeight.bold, color: rows[i].value >= 0 ? Colors.green : Colors.red)),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class PlansScreen extends StatelessWidget {
  const PlansScreen({super.key});

  static const _plans = <Plan>[
    Plan('free', 'مجانية', '\$0', ['3 إشارات يومياً', 'المفكرة الأساسية', 'الأكاديمية']),
    Plan('pro', 'احترافية', '\$19 / شهر', ['كل الإشارات', 'مراجعة AI للصفقات', 'المستشار الذكي']),
    Plan('elite', 'نخبة', '\$49 / شهر', ['كل مزايا الاحترافية', 'نسخ التداول', 'الدوري الأسبوعي المميز']),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الباقات')),
      body: ListenableBuilder(
        listenable: TradeStore.I,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('اختيار تجريبي — لا توجد عملية دفع فعلية', style: TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 12),
            ..._plans.map((p) {
              final current = TradeStore.I.plan == p.id;
              return Card(
                color: Theme.of(context).cardColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: current ? _kPrimary : Colors.transparent, width: 2)),
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Text(p.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      Text(p.price, style: const TextStyle(fontWeight: FontWeight.bold, color: _kPrimary)),
                    ]),
                    const SizedBox(height: 8),
                    ...p.features.map((f) => Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Row(children: [const Icon(Icons.check, size: 16, color: Colors.green), const SizedBox(width: 8), Text(f)]))),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: current
                          ? const OutlinedButton(onPressed: null, child: Text('باقتك الحالية'))
                          : FilledButton(onPressed: () => TradeStore.I.setPlan(p.id), child: const Text('اختيار')),
                    ),
                  ]),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class AcademyScreen extends StatelessWidget {
  const AcademyScreen({super.key});

  static const _lessons = <List<String>>[
    ['إدارة المخاطر', 'لا تخاطر بأكثر من 1–2% من رأس المال في صفقة واحدة. حدّد حجم اللوت من مسافة الوقف لا من حماسك. حدد حداً أقصى للخسارة اليومية وتوقف عنده.'],
    ['وقف الخسارة والهدف', 'ضع الوقف حيث تنتهي صلاحية فكرتك، والهدف بنسبة عائد/مخاطرة لا تقل عن 1:2. لا تحرّك الوقف بعيداً عن السعر بعد الدخول.'],
    ['قراءة الاتجاه', 'ابدأ من الإطار الأكبر (يومي/4 ساعات) لتحديد الاتجاه، ثم انزل إلى إطار أصغر للدخول. تداول مع الاتجاه أسهل غالباً من عكسه.'],
    ['علم نفس التداول', 'الخوف والطمع والانتقام أكبر أعداء المتداول. سجّل حالتك المزاجية في المفكرة وراجعها أسبوعياً، وخذ استراحة بعد خسارتين متتاليتين.'],
    ['الحسابات الإسلامية والسواب', 'السواب هو رسوم/فوائد إبقاء الصفقة ليلاً. الحسابات الإسلامية تُعفى منه لكن قد تُفرض رسوم بديلة. اقرأ شروط وسيطك جيداً.'],
    ['أهمية المفكرة', 'ما لا يُقاس لا يتحسّن. دوّن كل صفقة بسببها ونتيجتها وحالتك، ثم حلّل بياناتك بدل الاعتماد على الذاكرة.'],
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الأكاديمية')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('محتوى تعليمي عام وليس نصيحة مالية', style: TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 12),
          ..._lessons.asMap().entries.map((e) => Card(
                color: Theme.of(context).cardColor,
                child: ExpansionTile(
                  leading: CircleAvatar(radius: 14, backgroundColor: _kPrimary, child: Text('${e.key + 1}', style: const TextStyle(fontSize: 12, color: Colors.white))),
                  title: Text(e.value[0], style: const TextStyle(fontWeight: FontWeight.bold)),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  children: [Text(e.value[1], style: const TextStyle(height: 1.6))],
                ),
              )),
        ],
      ),
    );
  }
}