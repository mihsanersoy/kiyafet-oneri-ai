import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme/marble_background_painter.dart';
import '../../core/theme/optiwear_theme.dart';
import '../routine/routine_service.dart';

/// Göreli tarih biçimlendirici ("Az önce", "15 dakika önce", "2 gün önce" vb.)
/// Yalnızca gerçek `created_at` verisini kullanır; sahte alan üretmez.
String formatRelativeScenarioTime(dynamic rawCreatedAt) {
  if (rawCreatedAt == null) return '';
  final rawStr = rawCreatedAt.toString().trim();
  if (rawStr.isEmpty) return '';

  DateTime? parsed = DateTime.tryParse(rawStr);
  if (parsed == null) return rawStr;

  // SQLite UTC timestamp dönerse yerel zamana normalize et
  final now = DateTime.now();
  final localParsed = parsed.isUtc ? parsed.toLocal() : parsed;
  Duration diff = now.difference(localParsed);
  if (diff.isNegative) {
    diff = Duration.zero;
  }

  if (diff.inSeconds < 60) {
    return 'Az önce';
  } else if (diff.inMinutes < 60) {
    return '${diff.inMinutes} dakika önce';
  } else if (diff.inHours < 24) {
    return '${diff.inHours} saat önce';
  } else if (diff.inDays == 1) {
    return 'Dün';
  } else if (diff.inDays < 30) {
    return '${diff.inDays} gün önce';
  } else if (diff.inDays < 365) {
    final months = (diff.inDays / 30).floor();
    return '$months ay önce';
  } else {
    final years = (diff.inDays / 365).floor();
    return '$years yıl önce';
  }
}

class _PendingScenarioDeletion {
  final Map<String, dynamic> item;
  final int originalIndex;
  final Timer timer;

  _PendingScenarioDeletion({
    required this.item,
    required this.originalIndex,
    required this.timer,
  });
}

/// Senaryo Listesi Ekranı (`features/scenario/scenario_list_screen.dart`)
/// - Mermer temasını (`OptiWearTheme` & `MarbleCard`) kullanır.
/// - Yalnızca gerçek `id`, `scenario_text` ve `created_at` alanlarını gösterir (başlık/konum uydurmaz).
/// - READ: Liste görünümü, dokununca tam metin açılır/kapanır veya diyalogla incelenir,
///   Yükleniyor, Boş Liste ve Hata durumları ayrıdır, `RefreshIndicator` ile aşağı çekerek yenilenir.
/// - DELETE: Kaydırarak (`Dismissible`) ve çöp kutusu ikonuyla silme, animasyonlu çıkış,
///   5 saniyelik "Geri Al" `SnackBar`'ı; süre dolunca `DELETE` isteği gider, geri alınırsa hiç gitmez.
/// - TOPLU SİLME: Uzun basınca çoklu seçim modu, üst barda seçili sayısı ve "Sil" aksiyonu, tek onay diyaloğu.
class ScenarioListScreen extends StatefulWidget {
  final RoutineService routineService;

  const ScenarioListScreen({
    super.key,
    required this.routineService,
  });

  @override
  State<ScenarioListScreen> createState() => _ScenarioListScreenState();
}

class _ScenarioListScreenState extends State<ScenarioListScreen> {
  static const int _pageSize = 50;

  List<Map<String, dynamic>> _scenarios = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _errorMessage;

  // Dokununca tam metni açılan kayıtlar
  final Set<int> _expandedIds = <int>{};

  // Çoklu seçim (toplu silme) durumu
  final Set<int> _selectedIds = <int>{};
  bool _isSelectionMode = false;
  bool _isBulkDeleting = false;

  // 5 saniyelik Geri Al (Undo) bekleyen tekil silme işlemleri
  final Map<int, _PendingScenarioDeletion> _pendingDeletions =
      <int, _PendingScenarioDeletion>{};

  // Animasyonlu çıkış için kaldırılmakta olan ID'ler
  final Set<int> _removingIds = <int>{};

  @override
  void initState() {
    super.initState();
    _fetchScenarios(reset: true);
  }

  @override
  void dispose() {
    // Ekran kapanırken bekleyen silme zamanlayıcılarını hemen çalıştır
    for (final entry in _pendingDeletions.entries) {
      entry.value.timer.cancel();
      widget.routineService.deleteScenario(entry.key).ignore();
    }
    _pendingDeletions.clear();
    super.dispose();
  }

  Future<void> _fetchScenarios({bool reset = true}) async {
    if (reset) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
        _hasMore = true;
      });
    } else {
      if (_isLoadingMore || !_hasMore) return;
      setState(() => _isLoadingMore = true);
    }

    try {
      final offset = reset ? 0 : _scenarios.length;
      final fetched = await widget.routineService.getScenarios(
        limit: _pageSize,
        offset: offset,
      );

      // Bekleyen silme listesindeki ID'leri listede tekrar gösterme
      final filtered = fetched
          .where((item) => !_pendingDeletions.containsKey(item['id'] as int))
          .toList();

      if (!mounted) return;
      setState(() {
        if (reset) {
          _scenarios = filtered;
        } else {
          final existingIds = _scenarios.map((e) => e['id'] as int).toSet();
          for (final item in filtered) {
            if (!existingIds.contains(item['id'] as int)) {
              _scenarios.add(item);
            }
          }
        }
        _hasMore = fetched.length >= _pageSize;
        _isLoading = false;
        _isLoadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage =
            'Senaryo listesi yüklenirken bir bağlantı hatası oluştu.';
        _isLoading = false;
        _isLoadingMore = false;
      });
    }
  }

  void _enterSelectionMode(int initialId) {
    setState(() {
      _isSelectionMode = true;
      _selectedIds.add(initialId);
    });
  }

  void _toggleSelection(int id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        if (_selectedIds.isEmpty) {
          _isSelectionMode = false;
        }
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedIds.clear();
    });
  }

  void _selectAllOrClear() {
    setState(() {
      if (_selectedIds.length == _scenarios.length) {
        _selectedIds.clear();
        _isSelectionMode = false;
      } else {
        _selectedIds
          ..clear()
          ..addAll(_scenarios.map((e) => e['id'] as int));
      }
    });
  }

  /// Tekil silme: Önce varsa önceki bekleyen silmeyi tamamlar, kaydı animasyonla çıkarır,
  /// 5 saniyelik "Geri Al" SnackBar'ı açar. Geri alınırsa API isteği hiç gönderilmez.
  Future<void> _scheduleSingleDelete(
    Map<String, dynamic> item, {
    bool alreadyDismissedBySwipe = false,
  }) async {
    final id = item['id'] as int;
    final currentIndex = _scenarios.indexWhere((e) => (e['id'] as int) == id);
    if (currentIndex == -1) return;

    // İkonla silindiyse önce küçülerek çıkış animasyonunu oynat
    if (!alreadyDismissedBySwipe) {
      setState(() => _removingIds.add(id));
      await Future.delayed(const Duration(milliseconds: 220));
      if (!mounted) return;
    }

    final exactIndex = _scenarios.indexWhere((e) => (e['id'] as int) == id);
    if (exactIndex == -1) return;

    final removedItem = _scenarios[exactIndex];
    setState(() {
      _removingIds.remove(id);
      _scenarios.removeAt(exactIndex);
      _selectedIds.remove(id);
      if (_selectedIds.isEmpty) _isSelectionMode = false;
    });

    final timer = Timer(const Duration(seconds: 5), () {
      _commitSingleDelete(id);
    });

    _pendingDeletions[id] = _PendingScenarioDeletion(
      item: removedItem,
      originalIndex: exactIndex,
      timer: timer,
    );

    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 5),
        content: const Text('Senaryo silindi.'),
        action: SnackBarAction(
          label: 'Geri Al',
          onPressed: () => _undoSingleDelete(id),
        ),
      ),
    );
  }

  void _undoSingleDelete(int id) {
    final pending = _pendingDeletions.remove(id);
    if (pending == null) return;
    pending.timer.cancel();

    if (!mounted) return;
    setState(() {
      final insertIdx = pending.originalIndex.clamp(0, _scenarios.length);
      _scenarios.insert(insertIdx, pending.item);
    });
  }

  Future<void> _commitSingleDelete(int id) async {
    final pending = _pendingDeletions.remove(id);
    if (pending == null) return;
    pending.timer.cancel();

    try {
      await widget.routineService.deleteScenario(id);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        final insertIdx = pending.originalIndex.clamp(0, _scenarios.length);
        _scenarios.insert(insertIdx, pending.item);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Senaryo silinirken sunucu hatası oluştu; kayıt geri yüklendi.'),
        ),
      );
    }
  }

  Future<void> _confirmAndExecuteBulkDelete() async {
    if (_selectedIds.isEmpty || _isBulkDeleting) return;
    final count = _selectedIds.length;
    final ow = OptiWearTheme.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Seçili Senaryoları Sil'),
        content: Text(
          'Seçtiğiniz $count senaryo kaydı kalıcı olarak silinecek. Onaylıyor musunuz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: ow.danger,
              foregroundColor: const Color(0xFFFAFAF8),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('$count Kaydı Sil'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final idsToDelete = _selectedIds.toList();
    setState(() => _isBulkDeleting = true);

    try {
      // 100'lük paketler halinde tek transaction uç noktasına gönder
      for (int i = 0; i < idsToDelete.length; i += 100) {
        final chunk = idsToDelete.skip(i).take(100).toList();
        await widget.routineService.bulkDeleteScenarios(chunk);
      }

      if (!mounted) return;
      setState(() {
        _scenarios.removeWhere((item) => _selectedIds.contains(item['id'] as int));
        _selectedIds.clear();
        _isSelectionMode = false;
        _isBulkDeleting = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$count senaryo kaydı silindi.')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _isBulkDeleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Toplu silme işlemi sırasında bir hata oluştu.'),
        ),
      );
    }
  }

  void _onItemTap(Map<String, dynamic> item) {
    final id = item['id'] as int;
    if (_isSelectionMode) {
      _toggleSelection(id);
      return;
    }
    setState(() {
      if (_expandedIds.contains(id)) {
        _expandedIds.remove(id);
      } else {
        _expandedIds.add(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ow = OptiWearTheme.of(context);

    return Scaffold(
      backgroundColor: ow.background,
      appBar: AppBar(
        leading: _isSelectionMode
            ? IconButton(
                tooltip: 'Seçimi İptal Et',
                icon: const Icon(Icons.close),
                onPressed: _exitSelectionMode,
              )
            : null,
        title: Text(
          _isSelectionMode
              ? '${_selectedIds.length} seçili'
              : 'Senaryo Listesi',
        ),
        actions: [
          if (_isSelectionMode) ...[
            IconButton(
              tooltip: _selectedIds.length == _scenarios.length
                  ? 'Seçimi Temizle'
                  : 'Tümünü Seç',
              icon: Icon(
                _selectedIds.length == _scenarios.length
                    ? Icons.deselect_outlined
                    : Icons.select_all_outlined,
              ),
              onPressed: _scenarios.isEmpty ? null : _selectAllOrClear,
            ),
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: ow.danger,
                  foregroundColor: const Color(0xFFFAFAF8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                ),
                onPressed:
                    _isBulkDeleting ? null : _confirmAndExecuteBulkDelete,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: Text(_isBulkDeleting ? 'Siliniyor...' : 'Sil'),
              ),
            ),
          ] else if (_scenarios.isNotEmpty) ...[
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: ow.elevatedSurface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: ow.cardBorder),
                  ),
                  child: Text(
                    '${_scenarios.length} kayıt',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: ow.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const Positioned.fill(
            child: MarbleSurfaceBackground(),
          ),
          Positioned.fill(
            child: _buildBody(ow),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(OptiWearTheme ow) {
    // 1. YÜKLENİYOR DURUMU
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: ow.effectiveAccent),
            const SizedBox(height: 14),
            Text(
              'Senaryolar yükleniyor...',
              style: TextStyle(color: ow.textSecondary, fontSize: 13.5),
            ),
          ],
        ),
      );
    }

    // 2. HATA DURUMU
    if (_errorMessage != null) {
      return RefreshIndicator(
        color: ow.effectiveAccent,
        onRefresh: () => _fetchScenarios(reset: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 80),
            MarbleCard(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    size: 44,
                    color: ow.danger,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _errorMessage!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: ow.textPrimary,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => _fetchScenarios(reset: true),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Tekrar Dene'),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // 3. BOŞ LİSTE DURUMU
    if (_scenarios.isEmpty) {
      return RefreshIndicator(
        color: ow.effectiveAccent,
        onRefresh: () => _fetchScenarios(reset: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 80),
            MarbleCard(
              padding: const EdgeInsets.all(26),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.psychology_outlined,
                    size: 46,
                    color: ow.effectiveAccent,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Henüz kayıtlı senaryo bulunmuyor',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: ow.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Ana ekrandaki Termal Hafıza kartından deneyimlerinizi eklediğinizde burada listelenir.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: ow.textSecondary,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // 4. LİSTE DURUMU (Aşağı çekerek yenileme + Sayfalama + Kaydırarak/İkonla/Toplu Silme)
    return RefreshIndicator(
      color: ow.effectiveAccent,
      onRefresh: () => _fetchScenarios(reset: true),
      child: NotificationListener<ScrollNotification>(
        onNotification: (scrollInfo) {
          if (_hasMore &&
              !_isLoadingMore &&
              scrollInfo.metrics.pixels >=
                  scrollInfo.metrics.maxScrollExtent - 160) {
            _fetchScenarios(reset: false);
          }
          return false;
        },
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          itemCount: _scenarios.length + (_isLoadingMore ? 1 : 0),
          itemBuilder: (context, index) {
            if (index >= _scenarios.length) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: ow.effectiveAccent,
                    ),
                  ),
                ),
              );
            }

            final item = _scenarios[index];
            final id = item['id'] as int;
            final text = (item['scenario_text'] ?? '').toString();
            final relativeDate =
                formatRelativeScenarioTime(item['created_at']);
            final isExpanded = _expandedIds.contains(id);
            final isSelected = _selectedIds.contains(id);
            final isRemoving = _removingIds.contains(id);

            return AnimatedSize(
              key: ValueKey('scenario_size_$id'),
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              child: isRemoving
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Dismissible(
                        key: ValueKey('scenario_dismiss_$id'),
                        direction: _isSelectionMode
                            ? DismissDirection.none
                            : DismissDirection.endToStart,
                        onDismissed: (_) => _scheduleSingleDelete(
                          item,
                          alreadyDismissedBySwipe: true,
                        ),
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          decoration: BoxDecoration(
                            color: ow.danger.withOpacity(0.85),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Sil',
                                style: TextStyle(
                                  color: Color(0xFFFAFAF8),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              SizedBox(width: 8),
                              Icon(
                                Icons.delete_outline,
                                color: Color(0xFFFAFAF8),
                              ),
                            ],
                          ),
                        ),
                        child: GestureDetector(
                          onTap: () => _onItemTap(item),
                          onLongPress: () {
                            if (!_isSelectionMode) {
                              _enterSelectionMode(id);
                            } else {
                              _toggleSelection(id);
                            }
                          },
                          child: MarbleCard(
                            borderRadius: 16,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 15,
                              vertical: 13,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (_isSelectionMode)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      right: 12,
                                      top: 2,
                                    ),
                                    child: Icon(
                                      isSelected
                                          ? Icons.check_circle_rounded
                                          : Icons.radio_button_unchecked_rounded,
                                      color: isSelected
                                          ? ow.effectiveAccent
                                          : ow.textSecondary,
                                      size: 22,
                                    ),
                                  )
                                else
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      right: 12,
                                      top: 2,
                                    ),
                                    child: Icon(
                                      Icons.memory_rounded,
                                      color: ow.effectiveAccent,
                                      size: 20,
                                    ),
                                  ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      AnimatedSize(
                                        duration:
                                            const Duration(milliseconds: 180),
                                        alignment: Alignment.topLeft,
                                        child: Text(
                                          text,
                                          maxLines: isExpanded ? null : 2,
                                          overflow: isExpanded
                                              ? TextOverflow.visible
                                              : TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: ow.textPrimary,
                                            fontSize: 14,
                                            height: 1.42,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          if (relativeDate.isNotEmpty) ...[
                                            Icon(
                                              Icons.schedule_rounded,
                                              size: 13,
                                              color: ow.textSecondary,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              relativeDate,
                                              style: TextStyle(
                                                color: ow.textSecondary,
                                                fontSize: 11.5,
                                              ),
                                            ),
                                          ],
                                          if (text.length > 85) ...[
                                            const Spacer(),
                                            Text(
                                              isExpanded
                                                  ? 'Daralt ▲'
                                                  : 'Tamamını gör ▼',
                                              style: TextStyle(
                                                color: ow.effectiveAccent,
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                if (!_isSelectionMode)
                                  IconButton(
                                    tooltip: 'Senaryoyu Sil',
                                    visualDensity: VisualDensity.compact,
                                    icon: Icon(
                                      Icons.delete_outline_rounded,
                                      color: ow.danger,
                                      size: 20,
                                    ),
                                    onPressed: () =>
                                        _scheduleSingleDelete(item),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
            );
          },
        ),
      ),
    );
  }
}
