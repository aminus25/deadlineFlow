import 'package:flutter/material.dart';
import 'database_helper.dart';
import 'calendar_screen.dart';
import 'notification_service.dart';
import 'dart:async';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'stats_screen.dart';

class AppColors {
  static const primary = Color(0xFF4F6CF7);
  static const background = Color(0xFFF5F6FA);
  static const cardBg = Colors.white;
  static const textPrimary = Color(0xFF1A1D2E);
  static const textSecondary = Color(0xFF9095A0);
  static const priorityHigh = Color(0xFFFF5C5C);
  static const priorityMedium = Color(0xFFFFAB2E);
  static const priorityLow = Color(0xFF4CD97B);
}

const _ruMonths = [
  '', 'янв', 'фев', 'мар', 'апр', 'май', 'июн',
  'июл', 'авг', 'сен', 'окт', 'ноя', 'дек'
];

String _formatRuDate(DateTime dt) {
  return '${dt.day} ${_ruMonths[dt.month]} ${dt.year}, '
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.instance.init();
  runApp(const DeadlineFlowApp());
}

class DeadlineFlowApp extends StatelessWidget {
  const DeadlineFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
    title: 'DeadlineFlow',
    debugShowCheckedModeBanner: false,

    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],

    supportedLocales: const [
      Locale('ru', 'RU'),
    ],

    locale: const Locale('ru', 'RU'),

   theme: ThemeData(
      useMaterial3: true,
      colorSchemeSeed: AppColors.primary,
      scaffoldBackgroundColor: AppColors.background,
      fontFamily: 'Roboto',
    ),

    home: const MainShell(),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  final List<Widget> _pages = const [
    HomeScreen(),
    CalendarScreen(),
    StatsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        backgroundColor: Colors.white,
        elevation: 8,
        shadowColor: Colors.black12,
        indicatorColor: AppColors.primary.withOpacity(0.12),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.checklist_rounded), label: 'Задачи'),
          NavigationDestination(icon: Icon(Icons.calendar_month_rounded), label: 'Календарь'),
          NavigationDestination(icon: Icon(Icons.bar_chart_rounded), label: 'Статистика'), 
        ],
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

enum FilterType { all, active, done, overdue }

class _HomeScreenState extends State<HomeScreen> {
  FilterType _filter = FilterType.active;
  List<Deadline> _deadlines = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDeadlines();
  }

  Future<void> _loadDeadlines() async {
    setState(() => _isLoading = true);
    final deadlines = await DatabaseHelper.instance.readAll();

     //Проверяем просроченные — отправляем уведомление только один раз
    for (final d in deadlines) {
      if (!d.isDone && d.dueDate.isBefore(DateTime.now()) && !d.isOverdueNotified) {
        unawaited(NotificationService.instance.showOverdueNotification(d));
      }
    }

    setState(() {
      _deadlines = deadlines;
      _isLoading = false;
    });
  }

  List<Deadline> get _filtered {
    final now = DateTime.now();
    List<Deadline> list = switch (_filter) {
      FilterType.all     => [..._deadlines],
      FilterType.active  => _deadlines.where((d) => !d.isDone && !d.dueDate.isBefore(now)).toList(),
      FilterType.done    => _deadlines.where((d) => d.isDone).toList(),
      FilterType.overdue => _deadlines.where((d) => !d.isDone && d.dueDate.isBefore(now)).toList(),
    };

    list.sort((a, b) {
      if (a.isDone != b.isDone) return a.isDone ? 1 : -1;
      return a.dueDate.compareTo(b.dueDate);
    });

    return list;
  }

  int get _activeCount => _deadlines.where((d) => !d.isDone && !d.dueDate.isBefore(DateTime.now())).length;
  int get _overdueCount => _deadlines.where((d) => !d.isDone && d.dueDate.isBefore(DateTime.now())).length;

  Future<void> _toggleDone(Deadline d) async {
    d.isDone = !d.isDone;
    await DatabaseHelper.instance.update(d);
    unawaited(NotificationService.instance.scheduleForDeadline(d));
    await _loadDeadlines();
  }

  Future<void> _delete(Deadline d) async {
    await DatabaseHelper.instance.delete(d.id!);
    unawaited(NotificationService.instance.cancelForDeadline(d));
    await _loadDeadlines();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('«${d.title}» удалён'),
          action: SnackBarAction(
            label: 'Отмена',
            onPressed: () async {
              final created = await DatabaseHelper.instance.create(d);
              unawaited(NotificationService.instance.scheduleForDeadline(created));
              await _loadDeadlines();
            },
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          _buildFilterBar(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                    ? _buildEmptyState()
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                        itemCount: _filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) => _DeadlineCard(
                          deadline: _filtered[i],
                          onToggle: () => _toggleDone(_filtered[i]),
                          onDelete: () => _delete(_filtered[i]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('DeadlineFlow',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text('$_activeCount активных',
                        style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                    if (_overdueCount > 0) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.priorityHigh.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text('$_overdueCount просрочено',
                            style: const TextStyle(fontSize: 12, color: AppColors.priorityHigh, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          FloatingActionButton.small(
            heroTag: 'add_fab',
            onPressed: () => _showAddSheet(context),
            backgroundColor: AppColors.primary,
            child: const Icon(Icons.add, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          _filterChip(FilterType.active, 'Активные'),
          const SizedBox(width: 8),
          _filterChip(FilterType.overdue, 'Просрочено', badge: _overdueCount),
          const SizedBox(width: 8),
          _filterChip(FilterType.done, 'Выполненные'),
          const SizedBox(width: 8),
          _filterChip(FilterType.all, 'Все'),
        ],
      ),
    );
  }

  Widget _filterChip(FilterType f, String label, {int badge = 0}) {
    final isSelected = _filter == f;
    return GestureDetector(
      onTap: () => setState(() => _filter = f),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withOpacity(0.12) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? (f == FilterType.overdue ? AppColors.priorityHigh : AppColors.primary)
                : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSelected && f != FilterType.overdue)
              const Padding(
                padding: EdgeInsets.only(right: 4),
                child: Icon(Icons.check, size: 14, color: AppColors.primary),
              ),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected
                    ? (f == FilterType.overdue ? AppColors.priorityHigh : AppColors.primary)
                    : AppColors.textSecondary,
              ),
            ),
            if (badge > 0)
              Container(
                margin: const EdgeInsets.only(left: 6),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.priorityHigh,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('$badge',
                    style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final messages = {
      FilterType.active:  ('Нет активных задач', 'Нажмите + чтобы добавить'),
      FilterType.overdue: ('Нет просроченных задач', 'Отличная работа! 🎉'),
      FilterType.done:    ('Нет выполненных задач', 'Выполните задачу чтобы она появилась здесь'),
      FilterType.all:     ('Нет дедлайнов', 'Нажмите + чтобы добавить'),
    };
    final (title, subtitle) = messages[_filter]!;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _filter == FilterType.overdue ? Icons.check_circle_outline : Icons.task_alt,
            size: 64,
            color: AppColors.textSecondary,
          ),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        ],
      ),
    );
  }

  
    void _showAddSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => AddDeadlineSheet(
        onAdd: _addDeadline,   // ← используем отдельный метод
      ),
    );
  }

  Future<void> _addDeadline(Deadline d) async {
    try {
      debugPrint('📌 Пытаемся сохранить дедлайн: ${d.title}');

      final created = await DatabaseHelper.instance.create(d);
      
      debugPrint('✅ Дедлайн успешно сохранён! ID = ${created.id}');

      unawaited(NotificationService.instance.scheduleForDeadline(created));
      await _loadDeadlines();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Дедлайн добавлен ✓'), backgroundColor: Colors.green),
        );
      }
    } catch (e, stackTrace) {
      debugPrint('❌ ОШИБКА при сохранении дедлайна: $e');
      debugPrint('Stack trace: $stackTrace');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}


class _DeadlineCard extends StatelessWidget {
  final Deadline deadline;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  const _DeadlineCard({required this.deadline, required this.onToggle, required this.onDelete});

  bool get _isOverdue => !deadline.isDone && deadline.dueDate.isBefore(DateTime.now());

  Color get _timeColor {
    if (deadline.isDone) return AppColors.priorityLow;
    final diff = deadline.dueDate.difference(DateTime.now());
    if (diff.isNegative) return AppColors.priorityHigh;
    if (diff.inHours < 24) return AppColors.priorityMedium;
    if (diff.inDays <= 3) return const Color(0xFFFFCC00);
    return AppColors.primary;
  }

  Color get _priorityColor => switch (deadline.priority) {
    Priority.high   => AppColors.priorityHigh,
    Priority.medium => AppColors.priorityMedium,
    Priority.low    => AppColors.priorityLow,
  };

  String get _priorityLabel => switch (deadline.priority) {
    Priority.high   => 'Высокий',
    Priority.medium => 'Средний',
    Priority.low    => 'Низкий',
  };

  Color get _cardBackground {
    if (deadline.isDone) return const Color(0xFFF9F9F9);
    if (_isOverdue) return const Color(0xFFFFF5F5);
    final diff = deadline.dueDate.difference(DateTime.now());
    if (diff.inHours < 24) return const Color(0xFFFFFBF5);
    return Colors.white;
  }

  String _formatDate() {
    if (deadline.isDone) return 'Выполнено';
    final diff = deadline.dueDate.difference(DateTime.now());
    if (diff.isNegative) return 'Просрочено';
    if (diff.inHours < 1) return 'Через ${diff.inMinutes} мин';
    if (diff.inHours < 24) return 'Через ${diff.inHours}ч ${diff.inMinutes % 60}м';
    return 'Через ${diff.inDays} дн.';
  }

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key(deadline.id.toString()),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(color: AppColors.priorityHigh, borderRadius: BorderRadius.circular(16)),
        child: const Icon(Icons.delete_rounded, color: Colors.white),
      ),
      onDismissed: (_) => onDelete(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          color: _cardBackground,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 2))],
        ),
        child: IntrinsicHeight(
          child: Row(
            children: [
              Container(
                width: 4,
                decoration: BoxDecoration(
                  color: _priorityColor,
                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: onToggle,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: deadline.isDone ? AppColors.priorityLow : AppColors.textSecondary.withOpacity(0.4),
                      width: 2,
                    ),
                    color: deadline.isDone ? AppColors.priorityLow : Colors.transparent,
                  ),
                  child: deadline.isDone ? const Icon(Icons.check, size: 14, color: Colors.white) : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        deadline.title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: deadline.isDone ? AppColors.textSecondary : AppColors.textPrimary,
                          decoration: deadline.isDone ? TextDecoration.lineThrough : null,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const Icon(Icons.folder_outlined, size: 12, color: AppColors.textSecondary),
                          const SizedBox(width: 3),
                          Text(deadline.category,
                              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                        ],
                      ),
                      // Показываем дату создания если просрочено
                      if (_isOverdue) ...[
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            const Icon(Icons.schedule, size: 12, color: AppColors.priorityHigh),
                            const SizedBox(width: 3),
                            Text(
                              'Было: ${_formatRuDate(deadline.dueDate)}',
                              style: const TextStyle(fontSize: 11, color: AppColors.priorityHigh),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 12, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(_formatDate(),
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _timeColor)),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _priorityColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(_priorityLabel,
                          style: TextStyle(fontSize: 11, color: _priorityColor, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AddDeadlineSheet extends StatefulWidget {
  final Future<void> Function(Deadline) onAdd;
  const AddDeadlineSheet({super.key, required this.onAdd});

  @override
  State<AddDeadlineSheet> createState() => _AddDeadlineSheetState();
}

class _AddDeadlineSheetState extends State<AddDeadlineSheet> {
  final _titleController = TextEditingController();
  final _categoryController = TextEditingController();
  DateTime _dueDate = DateTime.now().add(const Duration(days: 1));
  Priority _priority = Priority.medium;
  bool _isSaving = false;

  Future<void> _pickDate() async {
    final picked = await showDateTimePicker(context, _dueDate);
    if (picked != null) setState(() => _dueDate = picked);
  }


 Future<void> _submit() async {
  if (_titleController.text.trim().isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Введите название задачи')),
    );
    return;
  }

  setState(() => _isSaving = true);

  final deadline = Deadline(
    title: _titleController.text.trim(),
    category: _categoryController.text.trim().isEmpty ? 'Без категории' : _categoryController.text.trim(),
    dueDate: _dueDate,
    priority: _priority,
    isDone: false,
    isOverdueNotified: false,
  );

  if (mounted) Navigator.pop(context);   // закрываем сразу

  await widget.onAdd(deadline);   // ← await чтобы видеть ошибки
}


  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 20, right: 20, top: 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Новый дедлайн',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
              const Spacer(),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
            ],
          ),
          const SizedBox(height: 12),
          _inputField(_titleController, 'Название задачи', Icons.edit_rounded),
          const SizedBox(height: 10),
          _inputField(_categoryController, 'Категория', Icons.folder_outlined),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: _pickDate,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today_rounded, color: AppColors.primary, size: 18),
                  const SizedBox(width: 10),
                  Text(
                    _formatRuDate(_dueDate),
                    style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
                  ),
                  const Spacer(),
                  const Icon(Icons.chevron_right, color: AppColors.textSecondary),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: Priority.values.map((p) {
              final labels = {Priority.low: 'Низкий', Priority.medium: 'Средний', Priority.high: 'Высокий'};
              final colors = {
                Priority.low: AppColors.priorityLow,
                Priority.medium: AppColors.priorityMedium,
                Priority.high: AppColors.priorityHigh,
              };
              final isSelected = _priority == p;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: GestureDetector(
                    onTap: () => setState(() => _priority = p),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: isSelected ? colors[p]!.withOpacity(0.15) : AppColors.background,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: isSelected ? colors[p]! : Colors.transparent, width: 1.5),
                      ),
                      child: Text(labels[p]!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600,
                            color: isSelected ? colors[p]! : AppColors.textSecondary,
                          )),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _isSaving
                  ? const SizedBox(height: 20, width: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Добавить дедлайн',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _inputField(TextEditingController c, String hint, IconData icon) {
    return TextField(
      controller: c,
      style: const TextStyle(color: AppColors.textPrimary),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.textSecondary),
        prefixIcon: Icon(icon, color: AppColors.primary, size: 18),
        filled: true,
        fillColor: AppColors.background,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      ),
    );
  }
}

Future<DateTime?> showDateTimePicker(BuildContext context, DateTime initial) async {
  final date = await showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: DateTime.now(),
    lastDate: DateTime.now().add(const Duration(days: 365)),
    locale: const Locale('ru'),
  );
  if (date == null) return null;
  if (!context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(initial),
  );
  if (time == null) return null;
  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}

