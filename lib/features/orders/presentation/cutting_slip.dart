import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tailor_khata/app/services.dart';
import 'package:tailor_khata/core/l10n/digit_formatter.dart';
import 'package:tailor_khata/core/media/media_store.dart';
import 'package:tailor_khata/core/time/date_format.dart';
import 'package:tailor_khata/core/ui/app_theme.dart';
import 'package:tailor_khata/core/ui/empty_state.dart';
import 'package:tailor_khata/features/measurements/domain/measurement.dart';
import 'package:tailor_khata/features/measurements/domain/measurement_format.dart';
import 'package:tailor_khata/features/measurements/presentation/measurement_providers.dart';
import 'package:tailor_khata/features/orders/domain/order.dart';
import 'package:tailor_khata/features/orders/domain/style_catalog.dart';
import 'package:tailor_khata/features/orders/presentation/order_providers.dart';
import 'package:tailor_khata/l10n/gen/app_localizations.dart';

/// Everything one garment needs on the slip.
class SlipItem {
  const SlipItem({
    required this.item,
    required this.garment,
    this.measurement,
    this.photos = const [],
  });

  final OrderItem item;
  final GarmentInfo? garment;
  final Measurement? measurement;
  final List<StoredImage> photos;
}

/// The cutting slip for the karigor: order, delivery, style, measurements and
/// reference photos on one page (M-9, S3-12). Drawn on a fixed white card so
/// the shared picture looks the same on every phone, in light or dark mode.
class CuttingSlipView extends StatelessWidget {
  const CuttingSlipView({
    required this.detail,
    required this.items,
    required this.shopName,
    required this.languageCode,
    required this.media,
    super.key,
  });

  static const double width = 380;

  final OrderDetail detail;
  final List<SlipItem> items;
  final String shopName;
  final String languageCode;
  final MediaStore media;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final bangla = languageCode == 'bn';
    String d(String s) => DigitFormatter.format(s, bangla: bangla);
    final order = detail.order;

    return Theme(
      data: AppTheme.light(Locale(languageCode)),
      child: Builder(
        builder: (context) {
          final theme = Theme.of(context);
          const ink = Color(0xFF111111);
          final base = theme.textTheme.bodyMedium?.copyWith(color: ink);
          return Container(
            key: const ValueKey('slip-card'),
            width: width,
            color: Colors.white,
            padding: const EdgeInsets.all(20),
            child: DefaultTextStyle(
              style: base ?? const TextStyle(color: ink),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    shopName,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(l10n.slipTitle, style: base),
                  const Divider(color: ink, thickness: 1.5, height: 20),
                  Text(
                    d(l10n.slipOrderNo(order.number)),
                    key: const ValueKey('slip-order-no'),
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: ink,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    detail.customerName,
                    style: theme.textTheme.titleLarge?.copyWith(color: ink),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${l10n.slipDelivery}: ${d(formatStoredDate(order.deliveryDate, languageCode))}',
                    key: const ValueKey('slip-delivery'),
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: ink,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (order.trialDate != null)
                    Text(
                      '${l10n.slipTrial}: ${d(formatStoredDate(order.trialDate!, languageCode))}',
                      style: base,
                    ),
                  if (order.urgent)
                    Text(
                      l10n.urgentBadge.toUpperCase(),
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: const Color(0xFFB3261E),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  if (order.note != null && order.note!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(order.note!, style: base),
                    ),
                  for (final entry in items) ...[
                    const Divider(color: ink, height: 28),
                    _SlipItemBlock(
                      entry: entry,
                      languageCode: languageCode,
                      media: media,
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SlipItemBlock extends StatelessWidget {
  const _SlipItemBlock({
    required this.entry,
    required this.languageCode,
    required this.media,
  });

  final SlipItem entry;
  final String languageCode;
  final MediaStore media;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final theme = Theme.of(context);
    const ink = Color(0xFF111111);
    final bangla = languageCode == 'bn';
    final item = entry.item;
    final garment = entry.garment;
    final m = entry.measurement;
    final style = StyleCatalog.summarize(
      garment?.key ?? '',
      item.style,
      languageCode,
    );
    final title = [
      garment?.label(languageCode) ?? '',
      if (item.qty > 1)
        '× ${DigitFormatter.format('${item.qty}', bangla: bangla)}',
    ].join(' ');
    final notes = [
      if (style.isNotEmpty) style,
      if (item.fabricSource != null)
        item.fabricSource == FabricSource.customer
            ? l10n.fabricCustomer
            : l10n.fabricShop,
      if (item.colour != null && item.colour!.isNotEmpty) item.colour!,
      if (item.note != null && item.note!.isNotEmpty) item.note!,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleLarge?.copyWith(
            color: ink,
            fontWeight: FontWeight.w800,
          ),
        ),
        for (final line in notes)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              line,
              style: theme.textTheme.bodyMedium?.copyWith(color: ink),
            ),
          ),
        const SizedBox(height: 8),
        Text(
          l10n.slipMeasurements,
          style: theme.textTheme.labelLarge?.copyWith(
            color: ink,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (m == null)
          Text(
            l10n.slipNoMeasurements,
            style: theme.textTheme.bodyMedium?.copyWith(color: ink),
          )
        else ...[
          Text(
            DigitFormatter.format(
              '${l10n.versionLabel(m.version)} · ${formatStoredDate(m.takenOn, languageCode)}',
              bangla: bangla,
            ),
            style: theme.textTheme.bodySmall?.copyWith(color: ink),
          ),
          const SizedBox(height: 4),
          for (final f in garment?.fields ?? const <FieldTemplate>[])
            if (m.values.containsKey(f.key))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 1.5),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        f.label(languageCode),
                        style: theme.textTheme.bodyMedium?.copyWith(color: ink),
                      ),
                    ),
                    Text(
                      formatLength(m.values[f.key]!, m.unit, bangla: bangla),
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: ink,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
        ],
        if (entry.photos.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final photo in entry.photos)
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.file(
                    media.resolve(photo.thumbPath),
                    width: 100,
                    height: 100,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox(
                      width: 100,
                      height: 100,
                      child: Icon(Icons.broken_image_outlined),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Garments of an order with their measurements and photos, loaded once per
/// change of the order.
final slipItemsProvider = FutureProvider.autoDispose
    .family<List<SlipItem>, String>((ref, orderId) async {
      final detail = await ref.watch(orderDetailProvider(orderId).future);
      if (detail == null) return const [];
      final measurements = ref.read(measurementRepositoryProvider);
      final attachments = ref.read(attachmentRepositoryProvider);
      final garments = await measurements.garments();
      final out = <SlipItem>[];
      for (final item in detail.items) {
        final photos = await attachments.list('order_item', item.id);
        out.add(
          SlipItem(
            item: item,
            garment: garments
                .where((g) => g.id == item.garmentTypeId)
                .firstOrNull,
            measurement: item.measurementSetId == null
                ? null
                : await measurements.byId(item.measurementSetId!),
            photos: [for (final p in photos) p.image],
          ),
        );
      }
      return out;
    });

/// Preview of the slip with a button that shares it as a picture. A picture
/// (not a PDF) keeps Bangla letters correctly joined everywhere.
class CuttingSlipScreen extends ConsumerStatefulWidget {
  const CuttingSlipScreen({required this.orderId, super.key});

  final String orderId;

  @override
  ConsumerState<CuttingSlipScreen> createState() => _CuttingSlipScreenState();
}

class _CuttingSlipScreenState extends ConsumerState<CuttingSlipScreen> {
  final GlobalKey _boundary = GlobalKey();
  bool _sharing = false;

  Future<Uint8List> _capture() async {
    final boundary =
        _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 3);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  }

  Future<void> _share(OrderDetail detail) async {
    final l10n = AppL10n.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _sharing = true);
    try {
      final bytes = await _capture();
      await ref
          .read(fileSharerProvider)
          .shareFile(bytes, fileName: 'slip-${detail.order.number}.png');
      messenger.showSnackBar(SnackBar(content: Text(l10n.slipShared)));
    } on Object {
      messenger.showSnackBar(SnackBar(content: Text(l10n.slipFailed)));
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final detail = ref.watch(orderDetailProvider(widget.orderId)).value;
    final settings = ref.watch(appSettingsProvider);
    if (detail == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.slipTitle)),
        body: EmptyState(
          icon: Icons.receipt_long_outlined,
          title: l10n.orderNotFound,
          body: '',
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.slipTitle),
        leading: BackButton(onPressed: () => context.pop()),
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('slip-share'),
        onPressed: _sharing ? null : () => _share(detail),
        icon: const Icon(Icons.share),
        label: Text(l10n.slipShare),
      ),
      body: Builder(
        builder: (context) {
          final items = ref.watch(slipItemsProvider(widget.orderId)).value;
          if (items == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
            child: Center(
              child: RepaintBoundary(
                key: _boundary,
                child: CuttingSlipView(
                  detail: detail,
                  items: items,
                  shopName: settings.shopName.isEmpty
                      ? l10n.appName
                      : settings.shopName,
                  languageCode: lang,
                  media: ref.watch(mediaStoreProvider),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
