import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/apps_controller.dart';
import '../theme.dart';

/// One app: its icon and name, what's installed and what's new, and the one
/// button that matters (Install, Update or Open).
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.entry, required this.controller});

  final AppEntry entry;
  final AppsController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final app = entry.app;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: entry.status == AppStatus.updateAvailable ? AppColors.accentSoft : AppColors.divider,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AppIcon(entry: entry),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(app.title, style: theme.textTheme.titleLarge),
                    _StatusChip(entry: entry),
                  ],
                ),
                const SizedBox(height: 4),
                Text(app.tagline, style: theme.textTheme.bodyMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 10),
                _Detail(entry: entry),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _MainButton(entry: entry, controller: controller),
                _MoreMenu(entry: entry, controller: controller),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AppIcon extends StatelessWidget {
  const _AppIcon({required this.entry});

  final AppEntry entry;

  @override
  Widget build(BuildContext context) {
    final letter = Container(
      color: AppColors.accentSoft,
      alignment: Alignment.center,
      child: Text(
        entry.app.title.characters.first,
        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.accent),
      ),
    );
    final icon = entry.app.icon;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.icon),
      child: SizedBox.square(
        dimension: 64,
        child: icon == null
            ? letter
            : Image.network(
                icon,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, _, _) => letter,
              ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.entry});

  final AppEntry entry;

  @override
  Widget build(BuildContext context) {
    final (label, highlight) = switch (entry.status) {
      AppStatus.updateAvailable => ('Update available', true),
      AppStatus.upToDate => ('Installed', false),
      AppStatus.notInstalled => ('Not installed', false),
      AppStatus.checking => (null, false),
    };
    if (label == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: highlight ? AppColors.accentSoft : null,
        border: highlight ? null : Border.all(color: AppColors.outline),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: highlight ? AppColors.accent : AppColors.textSecondary,
        ),
      ),
    );
  }
}

/// The line under the tagline: versions, the download's progress, or what
/// went wrong.
class _Detail extends StatelessWidget {
  const _Detail({required this.entry});

  final AppEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall;
    final task = entry.task;

    if (task != null) {
      final installing = entry.installed == null ? 'Installing' : 'Updating';
      final label = switch (task.stage) {
        TaskStage.waiting => 'Waiting for the one before it…',
        TaskStage.downloading => 'Downloading… ${((task.progress ?? 0) * 100).round()}%',
        TaskStage.closing => 'Closing ${entry.app.title}…',
        TaskStage.installing => '$installing…',
      };
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(
            value: task.stage == TaskStage.downloading ? task.progress : null,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 6),
          Text(label, style: small),
        ],
      );
    }

    final installed = entry.installed?.version;
    final latest = entry.latest;
    final parts = <String>[
      if (entry.installed != null) installed == null ? 'Installed' : 'Version $installed installed',
      if (latest != null && entry.status != AppStatus.upToDate)
        entry.installed == null
            ? 'Version ${latest.version} · ${_size(latest.size)}'
            : '${latest.version} available · ${_size(latest.size)}',
      if (entry.checking) 'Checking…',
      if (latest == null && entry.checkError != null) entry.checkError!,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(parts.join(' · '), style: small),
        if (entry.error != null) ...[
          const SizedBox(height: 4),
          Text(entry.error!, style: small?.copyWith(color: AppColors.danger)),
        ],
      ],
    );
  }

  static String _size(int bytes) {
    if (bytes <= 0) return '';
    final mb = bytes / (1024 * 1024);
    return mb >= 10 ? '${mb.round()} MB' : '${mb.toStringAsFixed(1)} MB';
  }
}

class _MainButton extends StatelessWidget {
  const _MainButton({required this.entry, required this.controller});

  final AppEntry entry;
  final AppsController controller;

  @override
  Widget build(BuildContext context) {
    final busy = entry.task != null;
    return switch (entry.status) {
      AppStatus.updateAvailable => FilledButton(
        onPressed: busy || entry.latest == null ? null : () => controller.install(entry),
        child: const Text('Update'),
      ),
      AppStatus.notInstalled => FilledButton(
        onPressed: busy || entry.latest == null ? null : () => controller.install(entry),
        child: const Text('Install'),
      ),
      AppStatus.upToDate => FilledButton.tonal(
        onPressed: busy || entry.exePath == null ? null : () => controller.open(entry),
        child: const Text('Open'),
      ),
      AppStatus.checking => const FilledButton(onPressed: null, child: Text('Checking')),
    };
  }
}

enum _Action { open, notes, folder, website, release, uninstall }

class _MoreMenu extends StatelessWidget {
  const _MoreMenu({required this.entry, required this.controller});

  final AppEntry entry;
  final AppsController controller;

  @override
  Widget build(BuildContext context) {
    final installed = entry.installed != null;
    final latest = entry.latest;
    final idle = entry.task == null;

    PopupMenuItem<_Action> item(_Action value, IconData icon, String label, {bool enabled = true}) =>
        PopupMenuItem(
          value: value,
          enabled: enabled,
          child: Row(children: [Icon(icon, size: 18), const SizedBox(width: 12), Text(label)]),
        );

    return PopupMenuButton<_Action>(
      tooltip: 'More',
      icon: const Icon(Icons.more_vert_rounded),
      onSelected: (action) => _run(context, action),
      itemBuilder: (_) => [
        if (installed && entry.status != AppStatus.upToDate)
          item(_Action.open, Icons.open_in_new_rounded, 'Open', enabled: idle && entry.exePath != null),
        if (latest != null) item(_Action.notes, Icons.notes_rounded, "What's new in ${latest.version}"),
        if (installed && entry.installed!.folder != null)
          item(_Action.folder, Icons.folder_open_rounded, 'Show install folder'),
        if (entry.app.page != null) item(_Action.website, Icons.language_rounded, 'Page on bersamamus.com'),
        if (latest != null) item(_Action.release, Icons.code_rounded, 'Release on GitHub'),
        if (installed && entry.installed!.uninstallCommand != null) ...[
          const PopupMenuDivider(),
          item(_Action.uninstall, Icons.delete_outline_rounded, 'Uninstall', enabled: idle),
        ],
      ],
    );
  }

  void _run(BuildContext context, _Action action) {
    switch (action) {
      case _Action.open:
        controller.open(entry);
      case _Action.notes:
        _showNotes(context);
      case _Action.folder:
        Process.start('explorer.exe', [entry.installed!.folder!]);
      case _Action.website:
        launchUrl(Uri.parse(entry.app.page!));
      case _Action.release:
        launchUrl(entry.latest!.pageUrl);
      case _Action.uninstall:
        controller.uninstall(entry);
    }
  }

  void _showNotes(BuildContext context) {
    final release = entry.latest!;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("What's new in ${entry.app.title} ${release.version}"),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 420),
          child: SingleChildScrollView(
            child: SelectableText(
              release.notes.isEmpty ? 'This release has no notes.' : release.notes,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => launchUrl(release.pageUrl), child: const Text('Open on GitHub')),
          FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }
}
