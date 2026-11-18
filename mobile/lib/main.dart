import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'core/background/weather_alert_worker.dart';
import 'core/network/api_client.dart';
import 'core/notifications/local_notification_service.dart';
import 'core/storage/secure_storage_service.dart';
import 'features/auth/auth_service.dart';
import 'features/routine/routine_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocalNotificationService.instance.init();
  await WeatherAlertWorker.initializeAndSchedule();
  runApp(const OptiWearApp());
}

class OptiWearApp extends StatefulWidget {
  const OptiWearApp({super.key});

  @override
  State<OptiWearApp> createState() => _OptiWearAppState();
}

class _OptiWearAppState extends State<OptiWearApp> {
  late final SecureStorageService _storage;
  late final ApiClient _apiClient;
  late final AuthService _authService;
  late final RoutineService _routineService;

  Map<String, dynamic>? _currentUser;
  bool _checkingSession = true;

  @override
  void initState() {
    super.initState();
    _storage = SecureStorageService();
    _apiClient = ApiClient(storage: _storage);
    _authService = AuthService(apiClient: _apiClient, storage: _storage);
    _routineService = RoutineService(apiClient: _apiClient);
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    try {
      final token = await _storage.getAccessToken();
      if (token != null && token.isNotEmpty) {
        final profile = await _authService.getMyProfile();
        if (mounted) {
          setState(() => _currentUser = profile);
        }
      }
    } catch (_) {
      await _storage.clearSession();
    } finally {
      if (mounted) {
        setState(() => _checkingSession = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OptiWear AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF38BDF8),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF020617),
      ),
      home: _checkingSession
          ? const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            )
          : _currentUser == null
              ? AuthScreen(
                  authService: _authService,
                  onAuthenticated: (user) => setState(() => _currentUser = user),
                )
              : RoutineDashboardScreen(
                  user: _currentUser!,
                  authService: _authService,
                  routineService: _routineService,
                  onLogout: () => setState(() => _currentUser = null),
                ),
    );
  }
}

class AuthScreen extends StatefulWidget {
  final AuthService authService;
  final ValueChanged<Map<String, dynamic>> onAuthenticated;

  const AuthScreen({
    super.key,
    required this.authService,
    required this.onAuthenticated,
  });

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _isLogin = true;
  bool _loading = false;
  String? _errorMessage;

  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  String _extractError(Object err) {
    if (err is DioException) {
      final data = err.response?.data;
      if (data is Map && data['detail'] != null) {
        return data['detail'].toString();
      }
    }
    return 'İşlem sırasında bir hata oluştu. Lütfen bilgilerinizi kontrol edin.';
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final user = _isLogin
          ? await widget.authService.login(
              email: _emailCtrl.text,
              password: _passwordCtrl.text,
            )
          : await widget.authService.register(
              email: _emailCtrl.text,
              password: _passwordCtrl.text,
              fullName: _nameCtrl.text,
              phoneNumber: _phoneCtrl.text,
            );
      widget.onAuthenticated(user);
    } catch (e) {
      setState(() => _errorMessage = _extractError(e));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              color: const Color(0xFF0F172A),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: Colors.white.withOpacity(0.12)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'OptiWear AI',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF38BDF8),
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _isLogin
                          ? 'Güvenli hesabınıza giriş yapın'
                          : 'Yeni OptiWear hesabı oluşturun',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 20),
                    if (_errorMessage != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.redAccent),
                        ),
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                        ),
                      ),
                    if (!_isLogin) ...[
                      TextField(
                        controller: _nameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Ad Soyad',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _phoneCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Telefon (+905...)',
                          prefixIcon: Icon(Icons.phone_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'E-posta Adresi',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passwordCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Şifre (En az 8 karakter, Büyük/Küçük Harf + Rakam)',
                        prefixIcon: Icon(Icons.lock_outline),
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _loading ? null : _submit,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(_loading
                            ? 'İşleniyor...'
                            : (_isLogin ? 'Giriş Yap' : 'Kayıt Ol')),
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(() {
                        _isLogin = !_isLogin;
                        _errorMessage = null;
                      }),
                      child: Text(_isLogin
                          ? 'Hesabınız yok mu? Kayıt Olun'
                          : 'Zaten hesabınız var mı? Giriş Yapın'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class RoutineDashboardScreen extends StatefulWidget {
  final Map<String, dynamic> user;
  final AuthService authService;
  final RoutineService routineService;
  final VoidCallback onLogout;

  const RoutineDashboardScreen({
    super.key,
    required this.user,
    required this.authService,
    required this.routineService,
    required this.onLogout,
  });

  @override
  State<RoutineDashboardScreen> createState() => _RoutineDashboardScreenState();
}

class _RoutineDashboardScreenState extends State<RoutineDashboardScreen> {
  int _selectedTabIndex = 0;

  // Sekme 1: Hızlı Hava Durumu Arama (Yapay Zekasız)
  final _quickCityCtrl = TextEditingController(text: 'Ankara');
  final _quickDistrictCtrl = TextEditingController();
  Map<String, dynamic>? _quickWeatherResult;
  bool _quickLoading = false;

  // Sekme 2: Seyahat / Bavul Hazırlama Modu
  final _travelCityCtrl = TextEditingController(text: 'Antalya');
  final _travelDistrictCtrl = TextEditingController(text: 'Kaş');
  final _travelStartCtrl = TextEditingController(text: '2026-11-20');
  final _travelEndCtrl = TextEditingController(text: '2026-11-24');
  Map<String, dynamic>? _travelResult;
  bool _travelLoading = false;

  // Sekme 3: Rutinler & Sabah Profili
  final _wakeTimeCtrl = TextEditingController(text: '07:30');
  final _cityCtrl = TextEditingController(text: 'İstanbul');
  final _districtCtrl = TextEditingController();
  final _heightCtrl = TextEditingController(text: '175');
  final _weightCtrl = TextEditingController(text: '75');
  String _sweating = 'Hayır';
  bool _notificationsEnabled = true;

  final _customTitleCtrl = TextEditingController(text: 'Sabah İşe Gidiş');
  final _customTimeCtrl = TextEditingController(text: '08:00');
  final _customDaysCtrl = TextEditingController(text: 'Pzt,Sal,Çar,Per,Cum');
  List<Map<String, dynamic>> _customRoutines = [];
  bool _smartEngagementEnabled = true;
  List<String> _scheduledSmartSlots = [];

  bool _loading = false;
  String? _statusMessage;
  Map<String, dynamic>? _morningBriefResult;

  @override
  void initState() {
    super.initState();
    _loadAllRoutines();
    _setupSmartDaytimeReminders(true);
  }

  Future<void> _setupSmartDaytimeReminders(bool enabled) async {
    final times = await LocalNotificationService.instance.scheduleSmartDaytimeReminders(
      enabled: enabled,
    );
    if (mounted) {
      setState(() {
        _smartEngagementEnabled = enabled;
        _scheduledSmartSlots = times;
      });
    }
  }

  Future<void> _loadAllRoutines() async {
    try {
      final r = await widget.routineService.getMyRoutine();
      final customList = await widget.routineService.getCustomRoutines();
      if (!mounted) return;
      setState(() {
        _wakeTimeCtrl.text = (r['wake_up_time'] ?? '07:30').toString();
        _cityCtrl.text = (r['sehir'] ?? 'İstanbul').toString();
        _districtCtrl.text = (r['ilce'] ?? '').toString();
        _heightCtrl.text = (r['boy'] ?? 175).toString();
        _weightCtrl.text = (r['kilo'] ?? 75).toString();
        _sweating = (r['terleme_egilimi'] ?? 'Hayır').toString();
        _notificationsEnabled = (r['notification_enabled'] ?? true) == true;
        _customRoutines = customList;
      });
      await WeatherAlertWorker.initializeAndSchedule(
        city: _cityCtrl.text,
        district: _districtCtrl.text,
      );
    } catch (_) {}
  }

  List<Color> _weatherGradient(String? status) {
    switch (status) {
      case 'Güneşli':
        return [const Color(0xFF0284C7), const Color(0xFFD97706)];
      case 'Yağmurlu':
        return [const Color(0xFF1E3A8A), const Color(0xFF0F172A)];
      case 'Karlı':
        return [const Color(0xFF38BDF8), const Color(0xFF1E293B)];
      case 'Rüzgarlı':
        return [const Color(0xFF0F766E), const Color(0xFF0F172A)];
      case 'Dolu':
        return [const Color(0xFF4C1D95), const Color(0xFF0F172A)];
      case 'Soğuk/Ayaz':
      default:
        return [const Color(0xFF1E40AF), const Color(0xFF020617)];
    }
  }

  Future<void> _searchQuickWeather() async {
    if (_quickCityCtrl.text.trim().isEmpty) return;
    setState(() => _quickLoading = true);
    try {
      final res = await widget.routineService.fetchQuickWeather(
        sehir: _quickCityCtrl.text,
        ilce: _quickDistrictCtrl.text,
      );
      if (mounted) setState(() => _quickWeatherResult = res);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Şehir hava durumu alınamadı.')),
        );
      }
    } finally {
      if (mounted) setState(() => _quickLoading = false);
    }
  }

  Future<void> _pickTravelDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 15)),
    );
    if (picked != null) {
      String fmt(DateTime d) =>
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      setState(() {
        _travelStartCtrl.text = fmt(picked.start);
        _travelEndCtrl.text = fmt(picked.end);
      });
    }
  }

  Future<void> _generateTravelPackingList() async {
    if (_travelCityCtrl.text.trim().isEmpty) return;
    setState(() => _travelLoading = true);
    try {
      final res = await widget.routineService.getTravelPackingRecommendation(
        hedefSehir: _travelCityCtrl.text,
        hedefIlce: _travelDistrictCtrl.text,
        baslangicTarihi: _travelStartCtrl.text,
        bitisTarihi: _travelEndCtrl.text,
        boy: double.tryParse(_heightCtrl.text) ?? 175.0,
        kilo: double.tryParse(_weightCtrl.text) ?? 75.0,
        terlemeEgilimi: _sweating,
      );
      if (mounted) setState(() => _travelResult = res);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Seyahat valizi önerisi alınırken hata oluştu.')),
        );
      }
    } finally {
      if (mounted) setState(() => _travelLoading = false);
    }
  }

  Future<void> _pickCustomRoutineTime() async {
    final parts = _customTimeCtrl.text.split(':');
    final initial = TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 8,
      minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0,
    );
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked != null) {
      final hh = picked.hour.toString().padLeft(2, '0');
      final mm = picked.minute.toString().padLeft(2, '0');
      setState(() => _customTimeCtrl.text = '$hh:$mm');
    }
  }

  Future<void> _addCustomRoutine() async {
    final title = _customTitleCtrl.text.trim();
    final timeStr = _customTimeCtrl.text.trim();
    final daysStr = _customDaysCtrl.text.trim();
    if (title.isEmpty || timeStr.isEmpty) return;

    setState(() {
      _loading = true;
      _statusMessage = null;
    });
    try {
      final created = await widget.routineService.createCustomRoutine(
        routineTitle: title,
        routineTime: timeStr,
        daysOfWeek: daysStr.isEmpty ? 'Pzt,Sal,Çar,Per,Cum' : daysStr,
      );

      final routineId = created['id'] as int;
      final notifyTime = created['notify_time']?.toString() ?? '';

      await LocalNotificationService.instance.scheduleRoutineBefore10Min(
        routineId: routineId,
        routineTitle: title,
        routineTimeHhMm: timeStr,
      );

      final updatedList = await widget.routineService.getCustomRoutines();
      if (mounted) {
        setState(() {
          _customRoutines = updatedList;
          _statusMessage =
              '✓ "$title" ($timeStr) eklendi! Bildirim 10 dk önce ($notifyTime) özel sesle çalacak.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _statusMessage = 'Rutin eklenirken hata oluştu (Saat HH:MM olmalı).');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _removeCustomRoutine(int id) async {
    try {
      await widget.routineService.deleteCustomRoutine(id);
      await LocalNotificationService.instance.cancelRoutineNotification(id);
      final updatedList = await widget.routineService.getCustomRoutines();
      if (mounted) {
        setState(() => _customRoutines = updatedList);
      }
    } catch (_) {}
  }

  Future<void> _saveRoutine() async {
    setState(() {
      _loading = true;
      _statusMessage = null;
    });
    try {
      await widget.routineService.updateRoutine(
        wakeUpTime: _wakeTimeCtrl.text.trim(),
        sehir: _cityCtrl.text.trim(),
        ilce: _districtCtrl.text.trim(),
        boy: double.tryParse(_heightCtrl.text) ?? 175.0,
        kilo: double.tryParse(_weightCtrl.text) ?? 75.0,
        terlemeEgilimi: _sweating,
        notificationEnabled: _notificationsEnabled,
      );
      await WeatherAlertWorker.initializeAndSchedule(
        city: _cityCtrl.text.trim(),
        district: _districtCtrl.text.trim(),
      );
      setState(() => _statusMessage = '✓ Profiliniz ve arka plan hava değişimi takipçisi güncellendi.');
    } catch (_) {
      setState(() => _statusMessage = 'Rutin kaydedilirken hata oluştu.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _runMorningBrief() async {
    setState(() {
      _loading = true;
      _statusMessage = null;
    });
    try {
      await _saveRoutine();
      final res = await widget.routineService.triggerMorningBrief();
      if (mounted) setState(() => _morningBriefResult = res);
    } catch (_) {
      setState(() => _statusMessage = 'Sabah kombin bildirimi alınamadı.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _testWeatherShiftNotificationNow() async {
    setState(() => _loading = true);
    try {
      final alertData = await widget.routineService.checkHourlyWeatherShift(
        sehir: _cityCtrl.text.trim(),
        ilce: _districtCtrl.text.trim(),
      );
      await LocalNotificationService.instance.showWeatherShiftAlert(
        title: alertData['bildirim_basligi']?.toString() ?? 'OptiWear Ani Hava Uyarısı',
        body: alertData['bildirim_mesaji']?.toString() ??
            'Gün içinde 8°C üzeri sıcaklık değişimi veya ani yağış bekleniyor!',
      );
      if (mounted) {
        setState(() => _statusMessage =
            '⚡ Ani hava değişimi bildirimi (weather_shift_alert sesiyle) gönderildi!');
      }
    } catch (_) {
      await LocalNotificationService.instance.showWeatherShiftAlert(
        title: 'OptiWear Ani Hava Uyarısı • ${_cityCtrl.text}',
        body: 'Dikkat! Gün içinde sıcaklık 8°C\'den fazla değişecek. Yanına ek katman almayı unutma!',
      );
      if (mounted) {
        setState(() => _statusMessage =
            '⚡ Test bildirimi (weather_shift_alert sesiyle) tetiklendi!');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _confirmAccountAction({required bool permanentDelete}) async {
    final passCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(permanentDelete ? 'Hesabı Kalıcı Sil (KVKK)' : 'Hesabı Dondur'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              permanentDelete
                  ? 'Tüm kişisel verileriniz ve hesabınız veritabanından kalıcı olarak silinecektir.'
                  : 'Hesabınız pasife alınacak (is_active=false) ve açık oturumlarınız kapatılacaktır.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Onay için mevcut şifreniz'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: permanentDelete ? Colors.red : Colors.orange,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(permanentDelete ? 'Kalıcı Olarak Sil' : 'Dondur'),
          ),
        ],
      ),
    );

    if (confirmed == true && passCtrl.text.isNotEmpty) {
      try {
        if (permanentDelete) {
          await widget.authService.deleteAccount(password: passCtrl.text);
        } else {
          await widget.authService.freezeAccount(password: passCtrl.text);
        }
        widget.onLogout();
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Şifre doğrulanamadı veya işlem başarısız.')),
          );
        }
      }
    }
  }

  Widget _buildQuickWeatherTab() {
    final status = _quickWeatherResult?['hava_durumu_durumu']?.toString();
    final colors = _weatherGradient(status);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            color: const Color(0xFF0F172A).withOpacity(0.85),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '🔍 Hızlı Şehir Hava Durumu Arama (AI Olmadan Anlık)',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Yapay zeka tokenı harcamadan başka şehirlerin anlık sıcaklığını, rüzgarını ve WMO durumunu görün.',
                    style: TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _quickCityCtrl,
                          decoration: const InputDecoration(
                            labelText: 'İl (Örn: İzmir)',
                            prefixIcon: Icon(Icons.location_city),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _quickDistrictCtrl,
                          decoration: const InputDecoration(
                            labelText: 'İlçe (İsteğe Bağlı)',
                            prefixIcon: Icon(Icons.place_outlined),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _quickLoading ? null : _searchQuickWeather,
                      icon: const Icon(Icons.search),
                      label: Text(_quickLoading ? 'Sorgulanıyor...' : 'Anlık Hava Durumunu Göster'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_quickWeatherResult != null) ...[
            const SizedBox(height: 18),
            Card(
              color: Colors.black.withOpacity(0.45),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: Colors.white.withOpacity(0.2)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  children: [
                    Text(
                      _quickWeatherResult!['sehir'].toString(),
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    Chip(
                      label: Text(
                        '${_quickWeatherResult!['hava_durumu_durumu']} (WMO: ${_quickWeatherResult!['wmo_kodu']})',
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      '${_quickWeatherResult!['sicaklik']}°C',
                      style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Hissedilen: ${_quickWeatherResult!['hissedilen_sicaklik']}°C  •  Rüzgar: ${_quickWeatherResult!['ruzgar_hizi']} km/s',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTravelPackingTab() {
    final forecasts = (_travelResult?['gunluk_tahminler'] as List?) ?? [];

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          color: const Color(0xFF0F172A),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '🧳 Seyahat Valizi & Bavul Hazırlama Modu (AI)',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Gideceğiniz şehrin çok günlük hava tahminini çekip VKE ve terleme profilinize göre valiz listesi çıkarır.',
                  style: TextStyle(fontSize: 12, color: Colors.white70),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _travelCityCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Hedef Şehir',
                          prefixIcon: Icon(Icons.flight_takeoff),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _travelDistrictCtrl,
                        decoration: const InputDecoration(
                          labelText: 'İlçe (İsteğe Bağlı)',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _travelStartCtrl,
                        readOnly: true,
                        onTap: _pickTravelDateRange,
                        decoration: const InputDecoration(
                          labelText: 'Başlangıç (YYYY-MM-DD)',
                          prefixIcon: Icon(Icons.date_range),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _travelEndCtrl,
                        readOnly: true,
                        onTap: _pickTravelDateRange,
                        decoration: const InputDecoration(
                          labelText: 'Bitiş (YYYY-MM-DD)',
                          prefixIcon: Icon(Icons.event),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _travelLoading ? null : _generateTravelPackingList,
                    icon: const Icon(Icons.luggage),
                    label: Text(
                      _travelLoading
                          ? 'Valiz Listesi Hazırlanıyor...'
                          : 'Seyahat Valizi ve Kombin Listesi Oluştur',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_travelResult != null) ...[
          const SizedBox(height: 16),
          Card(
            color: const Color(0xFF1E293B),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '📍 ${_travelResult!['hedef_sehir']} (${_travelResult!['gun_sayisi']} Günlük Valiz Önerisi)',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF38BDF8),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _travelResult!['valiz_onerisi'].toString(),
                    style: const TextStyle(height: 1.45),
                  ),
                  const SizedBox(height: 14),
                  const Divider(),
                  ...forecasts.map((d) {
                    final day = Map<String, dynamic>.from(d as Map);
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text('${day['tarih']} • ${day['hava_durumu_durumu']}'),
                      trailing: Text(
                        '${day['min_sicaklik']}°C / ${day['max_sicaklik']}°C  (${day['ruzgar_hizi']} km/s)',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildRoutinesAndAccountTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            color: const Color(0xFF0F172A),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '🔔 Özel Günlük Rutin Ekle (10 Dk Önce Sesli Uyarı)',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _customTitleCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Rutin Adı (Örn: Sabah 08:00 İşe Gidiş)',
                      prefixIcon: Icon(Icons.event_note),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _customTimeCtrl,
                          readOnly: true,
                          onTap: _pickCustomRoutineTime,
                          decoration: const InputDecoration(
                            labelText: 'Rutin Saati (HH:MM)',
                            prefixIcon: Icon(Icons.schedule),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _customDaysCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Günler (Pzt,Sal...)',
                            prefixIcon: Icon(Icons.calendar_today),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _loading ? null : _addCustomRoutine,
                      icon: const Icon(Icons.add_alarm),
                      label: const Text('Rutin Ekle ve 10 Dk Öncesine Sesli Bildirim Kur'),
                    ),
                  ),
                  if (_customRoutines.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    const Divider(),
                    ..._customRoutines.map(
                      (item) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.notifications_active, color: Color(0xFF38BDF8)),
                        title: Text('${item['routine_title']} • ${item['routine_time']}'),
                        subtitle: Text(
                          'Günler: ${item['days_of_week']} | Sesli Uyarı: ${item['notify_time']}',
                          style: const TextStyle(fontSize: 12, color: Colors.white70),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                          onPressed: () => _removeCustomRoutine(item['id'] as int),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            color: const Color(0xFF0F172A),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '⏰ Sabah Uyanma, Profil & Workmanager Hava Takibi',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _wakeTimeCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Uyanma Saati (HH:MM)',
                            prefixIcon: Icon(Icons.access_time),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SwitchListTile(
                          title: const Text('Sabah Bildirimi', style: TextStyle(fontSize: 13)),
                          value: _notificationsEnabled,
                          onChanged: (v) => setState(() => _notificationsEnabled = v),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _cityCtrl,
                          decoration: const InputDecoration(labelText: 'Sabit Şehir (İl)'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _districtCtrl,
                          decoration: const InputDecoration(labelText: 'İlçe'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _heightCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Boy (cm)'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _weightCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Kilo (kg)'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_statusMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        _statusMessage!,
                        style: const TextStyle(color: Colors.lightBlueAccent),
                      ),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _loading ? null : _saveRoutine,
                          child: const Text('Profili Kaydet'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: _loading ? null : _runMorningBrief,
                          child: const Text('Sabah Kombinimi Üret'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _loading ? null : _testWeatherShiftNotificationNow,
                      icon: const Icon(Icons.thunderstorm_outlined, color: Color(0xFF38BDF8)),
                      label: const Text('Ani Hava Değişimi Sesli Uyarısını Şimdi Test Et'),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Divider(),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      '🎲 Akıllı Gün İçi Hatırlatmalar (08:00 - 22:00 Rastgele)',
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      _smartEngagementEnabled
                          ? 'Gece 22:00-08:00 arası sessizdir. Bugünkü rastgele saatler: ${_scheduledSmartSlots.join(" • ")}'
                          : 'Rastgele gün içi hatırlatma bildirimleri kapalı.',
                      style: const TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                    value: _smartEngagementEnabled,
                    onChanged: (val) => _setupSmartDaytimeReminders(val),
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await LocalNotificationService.instance.triggerRandomEngagementSampleNow();
                        if (mounted) {
                          setState(() => _statusMessage =
                              '🎲 Rastgele gün içi hatırlatma bildirimi gönderildi!');
                        }
                      },
                      icon: const Icon(Icons.auto_awesome, color: Colors.amberAccent),
                      label: const Text('Rastgele Hatırlatma Bildirimini Şimdi Test Et'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_morningBriefResult != null) ...[
            const SizedBox(height: 16),
            Card(
              color: const Color(0xFF1E293B),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_morningBriefResult!['sehir']} • ${_morningBriefResult!['hava_durumu_durumu']} (${_morningBriefResult!['hissedilen_sicaklik']}°C)',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF38BDF8),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(_morningBriefResult!['oneri'].toString()),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.pause_circle_outline, color: Colors.orangeAccent),
                  label: const Text('Hesabı Dondur'),
                  onPressed: () => _confirmAccountAction(permanentDelete: false),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.delete_forever, color: Colors.redAccent),
                  label: const Text('Hesabı Sil (KVKK)'),
                  onPressed: () => _confirmAccountAction(permanentDelete: true),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _buildQuickWeatherTab(),
      _buildTravelPackingTab(),
      _buildRoutinesAndAccountTab(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text('OptiWear • ${widget.user['full_name'] ?? ''}'),
        actions: [
          IconButton(
            tooltip: 'Çıkış Yap',
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await widget.authService.logout();
              widget.onLogout();
            },
          ),
        ],
      ),
      body: pages[_selectedTabIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTabIndex,
        onDestinationSelected: (idx) => setState(() => _selectedTabIndex = idx),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.travel_explore),
            label: 'Hızlı Hava',
          ),
          NavigationDestination(
            icon: Icon(Icons.luggage_outlined),
            label: 'Seyahat Valizi',
          ),
          NavigationDestination(
            icon: Icon(Icons.alarm),
            label: 'Rutin & Hesap',
          ),
        ],
      ),
    );
  }
}
