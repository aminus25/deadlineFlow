import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'database_helper.dart';
import 'main.dart';

// Русские названия месяцев и дней
const _months = [
  '', 'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
  'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь'
];

const _daysOfWeek = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

// ── Экран календаря ───────────────────────────────────────────────────────────

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  List<Deadline> _allDeadlines = [];
  Map<DateTime, List<Deadline>> _events = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDeadlines();
  }

  Future<void> _loadDeadlines() async {
    setState(() => _isLoading = true);
    final deadlines = await DatabaseHelper.instance.readAll();
    setState(() {
      _allDeadlines = deadlines;
      _isLoading = false;
      _updateEvents();
    });
  }

  void _updateEvents() {
    _events = {};
    for (var deadline in _allDeadlines) {
      final date = DateTime(
        deadline.dueDate.year,
        deadline.dueDate.month,
        deadline.dueDate.day,
      );
      if (!_events.containsKey(date)) {
        _events[date] = [];
      }
      _events[date]!.add(deadline);
    }
  }

  List<Deadline> _getDeadlinesForDay(DateTime day) {
    final date = DateTime(day.year, day.month, day.day);
    return _events[date] ?? [];
  }

  Future<void> _toggleDone(Deadline d) async {
    d.isDone = !d.isDone;
    await DatabaseHelper.instance.update(d);
    await _loadDeadlines();
  }

  // Цвет маркера — по наивысшему приоритету задач в этот день
  Color _markerColor(DateTime day) {
    final tasks = _getDeadlinesForDay(day);
    if (tasks.isEmpty) return Colors.transparent;
    if (tasks.any((t) => t.priority == Priority.high && !t.isDone)) {
      return AppColors.priorityHigh;
    }
    if (tasks.any((t) => t.priority == Priority.medium && !t.isDone)) {
      return AppColors.priorityMedium;
    }
    if (tasks.any((t) => !t.isDone)) {
      return AppColors.priorityLow;
    }
    return AppColors.textSecondary; // все выполнены
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildHeader(),
                _buildCalendar(),
                const SizedBox(height: 8),
                Expanded(child: _buildTasksForSelectedDay()),
              ],
            ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
      child: Row(
        children: [
          const Text(
            'Календарь',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${_allDeadlines.where((d) => !d.isDone).length} активных',
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCalendar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TableCalendar(
        firstDay: DateTime.now().subtract(const Duration(days: 365)),
        lastDay: DateTime.now().add(const Duration(days: 365)),
        focusedDay: _focusedDay,
        startingDayOfWeek: StartingDayOfWeek.monday, // неделя с понедельника
        selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
        onDaySelected: (selectedDay, focusedDay) {
          setState(() {
            _selectedDay = selectedDay;
            _focusedDay = focusedDay;
          });
        },
        eventLoader: _getDeadlinesForDay,

        // Кастомный билдер маркеров — цвет по приоритету
        calendarBuilders: CalendarBuilders(
          markerBuilder: (context, day, events) {
            if (events.isEmpty) return const SizedBox.shrink();
            final color = _markerColor(day);
            return Positioned(
              bottom: 4,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: events.take(3).map((_) => Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                )).toList(),
              ),
            );
          },
          // Кастомный заголовок — русский месяц
          headerTitleBuilder: (context, day) {
            return Center(
              child: Text(
                '${_months[day.month]} ${day.year}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            );
          },
          // Кастомные дни недели — русские
          dowBuilder: (context, day) {
            final index = (day.weekday - 1) % 7;
            final isWeekend = day.weekday == 6 || day.weekday == 7;
            return Center(
              child: Text(
                _daysOfWeek[index],
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isWeekend ? Colors.red : AppColors.textSecondary,
                ),
              ),
            );
          },
        ),

        calendarStyle: CalendarStyle(
          selectedDecoration: const BoxDecoration(
            color: AppColors.primary,
            shape: BoxShape.circle,
          ),
          todayDecoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.3),
            shape: BoxShape.circle,
          ),
          weekendTextStyle: const TextStyle(color: Colors.red),
          outsideDaysVisible: false,
          markersMaxCount: 3,
        ),
        headerStyle: const HeaderStyle(
          formatButtonVisible: false,
          titleCentered: true,
          titleTextStyle: TextStyle(fontSize: 0), // скрыт — используем кастомный
          leftChevronIcon: Icon(Icons.chevron_left, color: AppColors.primary),
          rightChevronIcon: Icon(Icons.chevron_right, color: AppColors.primary),
        ),
        daysOfWeekStyle: const DaysOfWeekStyle(
          dowTextFormatter: null,
        ),
      ),
    );
  }

  Widget _buildTasksForSelectedDay() {
    final tasks = _getDeadlinesForDay(_selectedDay);

    if (tasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.event_available,
                size: 48, color: AppColors.textSecondary),
            const SizedBox(height: 12),
            Text(
              'Нет задач на ${_selectedDay.day} ${_months[_selectedDay.month]}',
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text(
            '${_selectedDay.day} ${_months[_selectedDay.month]} — ${tasks.length} задач',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            itemCount: tasks.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, index) => _CalendarTaskCard(
              deadline: tasks[index],
              onToggle: () => _toggleDone(tasks[index]),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Карточка задачи для календаря ─────────────────────────────────────────────

class _CalendarTaskCard extends StatelessWidget {
  final Deadline deadline;
  final VoidCallback onToggle;

  const _CalendarTaskCard({
    required this.deadline,
    required this.onToggle,
  });

  Color get _priorityColor => switch (deadline.priority) {
        Priority.high => AppColors.priorityHigh,
        Priority.medium => AppColors.priorityMedium,
        Priority.low => AppColors.priorityLow,
      };

  String get _priorityLabel => switch (deadline.priority) {
        Priority.high => 'Высокий',
        Priority.medium => 'Средний',
        Priority.low => 'Низкий',
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: deadline.isDone ? const Color(0xFFF9F9F9) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(color: _priorityColor, width: 4),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        leading: GestureDetector(
          onTap: onToggle,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: deadline.isDone
                    ? AppColors.priorityLow
                    : AppColors.textSecondary.withOpacity(0.4),
                width: 2,
              ),
              color: deadline.isDone ? AppColors.priorityLow : Colors.transparent,
            ),
            child: deadline.isDone
                ? const Icon(Icons.check, size: 14, color: Colors.white)
                : null,
          ),
        ),
        title: Text(
          deadline.title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: deadline.isDone
                ? AppColors.textSecondary
                : AppColors.textPrimary,
            decoration: deadline.isDone ? TextDecoration.lineThrough : null,
          ),
        ),
        subtitle: Row(
          children: [
            const Icon(Icons.book_rounded,
                size: 11, color: AppColors.textSecondary),
            const SizedBox(width: 3),
            Text(
              deadline.category,
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: _priorityColor.withOpacity(0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            _priorityLabel,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: _priorityColor,
            ),
          ),
        ),
      ),
    );
  }
}