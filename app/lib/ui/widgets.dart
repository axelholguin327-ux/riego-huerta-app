// Componentes reutilizables de la guía de estilo.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme.dart';

// ------------------------------------------------------------- formato ---

String timeAgo(DateTime? t, [DateTime? now]) {
  if (t == null) return 'sin datos';
  final d = (now ?? DateTime.now()).difference(t);
  if (d.inSeconds < 60) return 'hace ${d.inSeconds.clamp(0, 59)} s';
  if (d.inMinutes < 60) return 'hace ${d.inMinutes} min';
  if (d.inHours < 24) return 'hace ${d.inHours} h';
  return 'hace ${d.inDays} d';
}

/// "09:14", "Ayer 18:05" o "12 oct 09:14".
String shortDate(DateTime t) {
  final now = DateTime.now();
  final hm = DateFormat('HH:mm').format(t);
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(t.year, t.month, t.day);
  if (day == today) return hm;
  if (day == today.subtract(const Duration(days: 1))) return 'Ayer $hm';
  const m = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
  return '${t.day} ${m[t.month - 1]} $hm';
}

String fmtDuration(Duration d) =>
    d.inMinutes >= 1 ? '${d.inMinutes} min ${d.inSeconds % 60} s' : '${d.inSeconds} s';

// ------------------------------------------------------------- encabezado ---

/// AppBar verde con título y subtítulo, como en el prototipo.
PreferredSizeWidget header(String title, String subtitle, {List<Widget>? actions, bool back = false}) {
  return AppBar(
    toolbarHeight: 72,
    automaticallyImplyLeading: back,
    titleSpacing: back ? 0 : 16,
    actions: actions,
    title: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title),
        Text(subtitle, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: Color(0xDDFFFFFF))),
      ],
    ),
  );
}

// ------------------------------------------------------------- cards ---

class SectionCard extends StatelessWidget {
  final String? title;
  final Widget? trailing;
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  const SectionCard({super.key, this.title, this.trailing, required this.child,
      this.padding = const EdgeInsets.all(AppSpace.s4), this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title != null) ...[
                Row(children: [
                  Expanded(child: Text(title!, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
                  ?trailing,
                ]),
                const SizedBox(height: AppSpace.s3),
              ],
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class MetricCard extends StatelessWidget {
  final String label, value, unit, caption;
  const MetricCard({super.key, required this.label, required this.value, required this.unit, required this.caption});

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.texto2)),
        Text.rich(TextSpan(children: [
          TextSpan(text: value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, height: 1.15)),
          TextSpan(text: ' $unit', style: const TextStyle(fontSize: 14, color: AppColors.texto2)),
        ])),
        Text(caption, style: const TextStyle(fontSize: 12, color: AppColors.texto2)),
      ]),
    );
  }
}

// ------------------------------------------------------------- chips ---

enum ChipKind { neutral, ok, warn, error, info }

class StatusChip extends StatelessWidget {
  final String text;
  final ChipKind kind;
  final IconData? icon;
  const StatusChip(this.text, {super.key, this.kind = ChipKind.neutral, this.icon});

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (kind) {
      ChipKind.ok => (AppColors.verdeClaro, AppColors.verdeOscuro),
      ChipKind.warn => (AppColors.ambarClaro, AppColors.ambarTexto),
      ChipKind.error => (AppColors.rojoClaro, AppColors.rojo),
      ChipKind.info => (AppColors.azulClaro, const Color(0xFF1E5FB8)),
      ChipKind.neutral => (AppColors.gris, AppColors.texto2),
    };
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 14, color: fg), const SizedBox(width: 4)],
        Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
      ]),
    );
  }
}

/// Ícono en círculo de 36 px con el color de estado (listas).
class StatusIcon extends StatelessWidget {
  final IconData icon;
  final ChipKind kind;
  const StatusIcon(this.icon, {super.key, this.kind = ChipKind.info});

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (kind) {
      ChipKind.ok => (AppColors.verdeClaro, AppColors.verde),
      ChipKind.warn => (AppColors.ambarClaro, AppColors.ambar),
      ChipKind.error => (AppColors.rojoClaro, AppColors.rojo),
      ChipKind.info => (AppColors.azulClaro, AppColors.azul),
      ChipKind.neutral => (AppColors.gris, AppColors.texto2),
    };
    return CircleAvatar(radius: 18, backgroundColor: bg, child: Icon(icon, size: 20, color: fg));
  }
}

class ListRow extends StatelessWidget {
  final Widget leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  const ListRow({super.key, required this.leading, required this.title, this.subtitle, this.trailing, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.s3),
        child: Row(children: [
          leading,
          const SizedBox(width: AppSpace.s3),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              if (subtitle != null) Text(subtitle!, style: const TextStyle(fontSize: 12, color: AppColors.texto2)),
            ]),
          ),
          ?trailing,
        ]),
      ),
    );
  }
}

/// Lista con divisores de 1 px dentro de una card.
class DividedList extends StatelessWidget {
  final List<Widget> children;
  final String empty;
  const DividedList({super.key, required this.children, this.empty = 'Sin registros'});

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.s3),
        child: Text(empty, style: const TextStyle(color: AppColors.texto2, fontSize: 13)),
      );
    }
    return Column(children: [
      for (var i = 0; i < children.length; i++) ...[
        if (i > 0) const Divider(height: 1, color: AppColors.borde),
        children[i],
      ]
    ]);
  }
}

// ------------------------------------------------------------- avisos ---

class InfoBanner extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? text;
  final ChipKind kind;
  final VoidCallback? onTap;
  const InfoBanner({super.key, required this.icon, required this.title, this.text, this.kind = ChipKind.warn, this.onTap});

  @override
  Widget build(BuildContext context) {
    final (bg, border, fg) = switch (kind) {
      ChipKind.error => (AppColors.rojoClaro, const Color(0xFFF2C4C4), AppColors.rojo),
      ChipKind.info => (AppColors.azulClaro, const Color(0xFFC3DAF9), const Color(0xFF1E5FB8)),
      _ => (AppColors.ambarClaro, const Color(0xFFF7CFA8), const Color(0xFF8A4A12)),
    };
    return Material(
      color: bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: border)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.s4, vertical: AppSpace.s3),
          child: Row(children: [
            Icon(icon, color: fg),
            const SizedBox(width: AppSpace.s3),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: fg)),
                if (text != null) Text(text!, style: TextStyle(fontSize: 12, color: fg)),
              ]),
            ),
            if (onTap != null) Icon(Icons.chevron_right_rounded, color: fg),
          ]),
        ),
      ),
    );
  }
}

/// Muestra un mensaje breve (toast) sobre la barra inferior.
void toast(BuildContext context, String msg, {IconData icon = Icons.check_circle_rounded, bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      backgroundColor: error ? AppColors.rojo : AppColors.texto,
      content: Row(children: [
        Icon(icon, color: error ? Colors.white : const Color(0xFF7CE3A1)),
        const SizedBox(width: 10),
        Expanded(child: Text(msg)),
      ]),
    ));
}

/// Diálogo de confirmación con el estilo de la app. Regresa true si se acepta.
Future<bool> confirm(BuildContext context,
    {required String title, required String text, required IconData icon, required String ok, bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      icon: CircleAvatar(
        radius: 24,
        backgroundColor: danger ? AppColors.rojoClaro : AppColors.azulClaro,
        child: Icon(icon, color: danger ? AppColors.rojo : AppColors.azul),
      ),
      title: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      content: Text(text, style: const TextStyle(color: AppColors.texto2)),
      actions: [
        Row(children: [
          Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar'))),
          const SizedBox(width: AppSpace.s2),
          Expanded(
            child: danger
                ? OutlinedButton(
                    style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.rojo, side: const BorderSide(color: AppColors.rojo, width: 1.5)),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text(ok))
                : FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ok)),
          ),
        ]),
      ],
    ),
  );
  return r ?? false;
}

/// Vista estándar para un AsyncValue con error.
class ErrorView extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;
  const ErrorView(this.error, {super.key, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpace.s4),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.cloud_off_rounded, size: 40, color: AppColors.texto2),
        const SizedBox(height: AppSpace.s2),
        Text('$error', textAlign: TextAlign.center, style: const TextStyle(color: AppColors.texto2)),
        const SizedBox(height: AppSpace.s3),
        OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh_rounded), label: const Text('Reintentar')),
      ]),
    );
  }
}
