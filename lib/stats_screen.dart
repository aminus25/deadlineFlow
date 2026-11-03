import 'package:flutter/material.dart';
import 'database_helper.dart';
import 'main.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  List<Deadline> _deadlines = [];
  bool _isLoading = true;

  // Статистика
  int _totalTasks = 0;
  int _completedTasks = 0;
  int _activeTasks = 0;
  int _overdueTasks = 0;
  double _completionRate = 0.0;

  // Статистика по приоритетам
  Map<Priority, int> _totalByPriority = {};
  Map<Priority, int> _completedByPriority = {};

  // Статистика по категориям
  Map<String, int> _tasksByCategory = {};

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() => _isLoading = true);
    final deadlines = await DatabaseHelper.instance.readAll();
    _deadlines = deadlines;
    _calculateStats();
    setState(() => _isLoading = false);
  }

  void _calculateStats() {
    // Общая статистика
    _totalTasks = _deadlines.length;
    _completedTasks = _deadlines.where((d) => d.isDone).length;
    _activeTasks = _deadlines.where((d) => !d.isDone && !d.dueDate.isBefore(DateTime.now())).length;
    _overdueTasks = _deadlines.where((d) => !d.isDone && d.dueDate.isBefore(DateTime.now())).length;
    
    _completionRate = _totalTasks > 0 
        ? (_completedTasks / _totalTasks) * 100 
        : 0.0;

    // Статистика по приоритетам
    for (var priority in Priority.values) {
      _totalByPriority[priority] = _deadlines.where((d) => d.priority == priority).length;
      _completedByPriority[priority] = _deadlines.where((d) => d.priority == priority && d.isDone).length;
    }

    // Статистика по категориям (топ 5)
    _tasksByCategory = {};
    for (var deadline in _deadlines) {
      _tasksByCategory[deadline.category] = (_tasksByCategory[deadline.category] ?? 0) + 1;
    }
    
    // Сортируем по убыванию и берем топ 5
    final sorted = _tasksByCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    _tasksByCategory = Map.fromEntries(sorted.take(5));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadStats,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 20),
                    _buildSummaryCards(),
                    const SizedBox(height: 24),
                    _buildPriorityChart(),
                    const SizedBox(height: 24),
                    if (_tasksByCategory.isNotEmpty) _buildCategoryChart(),
                    const SizedBox(height: 24),
                    _buildUpcomingDeadlines(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Text(
          'Статистика',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const Spacer(),
        IconButton(
          onPressed: _loadStats,
          icon: const Icon(Icons.refresh, color: AppColors.primary),
        ),
      ],
    );
  }

  Widget _buildSummaryCards() {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.3,
      children: [
        _StatCard(
          title: 'Всего задач',
          value: _totalTasks,
          icon: Icons.task_alt,
          color: AppColors.primary,
        ),
        _StatCard(
          title: 'Выполнено',
          value: _completedTasks,
          icon: Icons.check_circle,
          color: AppColors.priorityLow,
        ),
        _StatCard(
          title: 'Активных',
          value: _activeTasks,
          icon: Icons.play_circle,
          color: AppColors.priorityMedium,
        ),
        _StatCard(
          title: 'Просрочено',
          value: _overdueTasks,
          icon: Icons.warning,
          color: AppColors.priorityHigh,
        ),
        _StatCard(
          title: 'Прогресс',
          value: '${_completionRate.toStringAsFixed(0)}%',
          icon: Icons.percent,
          color: Colors.purple,
        ),
      ],
    );
  }

  Widget _buildPriorityChart() {
    return Container(
      padding: const EdgeInsets.all(16),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '📊 По приоритетам',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          _buildPriorityBar(
            'Высокий',
            _totalByPriority[Priority.high] ?? 0,
            _completedByPriority[Priority.high] ?? 0,
            AppColors.priorityHigh,
          ),
          const SizedBox(height: 12),
          _buildPriorityBar(
            'Средний',
            _totalByPriority[Priority.medium] ?? 0,
            _completedByPriority[Priority.medium] ?? 0,
            AppColors.priorityMedium,
          ),
          const SizedBox(height: 12),
          _buildPriorityBar(
            'Низкий',
            _totalByPriority[Priority.low] ?? 0,
            _completedByPriority[Priority.low] ?? 0,
            AppColors.priorityLow,
          ),
        ],
      ),
    );
  }

  Widget _buildPriorityBar(String label, int total, int completed, Color color) {
    final percentage = total > 0 ? (completed / total) * 100 : 0.0;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            Text(
              '$completed/$total',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LinearProgressIndicator(
            value: percentage / 100,
            backgroundColor: color.withOpacity(0.2),
            color: color,
            minHeight: 8,
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryChart() {
    return Container(
      padding: const EdgeInsets.all(16),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '🏷️ По категориям',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          ..._tasksByCategory.entries.map((entry) {
            final percentage = (entry.value / _totalTasks) * 100;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          entry.key,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${entry.value} (${percentage.toStringAsFixed(0)}%)',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      value: percentage / 100,
                      backgroundColor: AppColors.primary.withOpacity(0.1),
                      color: AppColors.primary,
                      minHeight: 6,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildUpcomingDeadlines() {
    final now = DateTime.now();
    final nextDeadlines = _deadlines
        .where((d) => !d.isDone && d.dueDate.isAfter(now))
        .toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));

    return Container(
      padding: const EdgeInsets.all(16),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '🎯 Ближайшие дедлайны',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          if (nextDeadlines.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  'Нет активных дедлайнов',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            )
          else
            ...nextDeadlines.take(3).map((deadline) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _getPriorityColor(deadline.priority),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          deadline.title,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          _formatRelativeDate(deadline.dueDate),
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )),
        ],
      ),
    );
  }

  Color _getPriorityColor(Priority priority) {
    switch (priority) {
      case Priority.high: return AppColors.priorityHigh;
      case Priority.medium: return AppColors.priorityMedium;
      case Priority.low: return AppColors.priorityLow;
    }
  }

  String _formatRelativeDate(DateTime date) {
    final now = DateTime.now();
    final diff = date.difference(now);
    
    if (diff.inDays == 0) return 'сегодня';
    if (diff.inDays == 1) return 'завтра';
    if (diff.inDays < 7) return 'через ${diff.inDays} дн.';
    return '${date.day}.${date.month}.${date.year}';
  }
}

// Карточка статистики
class _StatCard extends StatelessWidget {
  final String title;
  final dynamic value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 28, color: color),
          const SizedBox(height: 8),
          Text(
            value.toString(),
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}