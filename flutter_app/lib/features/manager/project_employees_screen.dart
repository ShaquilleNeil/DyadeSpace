import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/projects_providers.dart';
import '../shared/widgets/employee_row.dart';
import '../shared/widgets/search_field.dart';

class ProjectEmployeesScreen extends ConsumerStatefulWidget {
  const ProjectEmployeesScreen({super.key, required this.projectId});

  final String projectId;

  @override
  ConsumerState<ProjectEmployeesScreen> createState() => _ProjectEmployeesScreenState();
}

class _ProjectEmployeesScreenState extends ConsumerState<ProjectEmployeesScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final projectAsync = ref.watch(projectByIdProvider(widget.projectId));
    final employeesAsync = ref.watch(projectEmployeesProvider(widget.projectId));

    return Scaffold(
      appBar: AppBar(title: Text(projectAsync.value?.name ?? 'Loading project…')),
      body: SafeArea(
        child: employeesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => Center(child: Text('Error: $e')),
          data: (employees) {
            final query = _query.toLowerCase();
            final displayed = query.trim().isEmpty
                ? employees
                : employees.where((e) => e.fullName.toLowerCase().contains(query)).toList();

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Text('Employees (${employees.length})',
                      style: Theme.of(context).textTheme.labelMedium),
                ),
                SearchField(onChanged: (value) => setState(() => _query = value)),
                const Divider(height: 1),
                Expanded(
                  child: ListView.separated(
                    itemCount: displayed.length,
                    separatorBuilder: (context, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final emp = displayed[index];
                      return EmployeeRow(
                        employee: emp,
                        onRemove: () => ref
                            .read(projectControllerProvider)
                            .removeEmployeeFromProject(widget.projectId, emp.id),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
