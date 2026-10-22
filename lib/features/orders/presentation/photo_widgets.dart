import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tailor_khata/app/services.dart';
import 'package:tailor_khata/core/media/media_store.dart';
import 'package:tailor_khata/core/services/photo_source.dart';
import 'package:tailor_khata/features/orders/domain/photo_attachment.dart';
import 'package:tailor_khata/features/orders/presentation/order_draft.dart';
import 'package:tailor_khata/features/orders/presentation/order_providers.dart';
import 'package:tailor_khata/l10n/gen/app_localizations.dart';

/// Small square preview of a stored photo. Tap to see it large; the optional
/// remove button deletes it.
class PhotoThumb extends ConsumerWidget {
  const PhotoThumb({
    required this.image,
    this.onRemove,
    this.size = 72,
    super.key,
  });

  final StoredImage image;
  final VoidCallback? onRemove;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final media = ref.watch(mediaStoreProvider);
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => showDialog<void>(
              context: context,
              builder: (_) => Dialog(
                child: InteractiveViewer(
                  child: Image.file(
                    media.resolve(image.path),
                    errorBuilder: (_, _, _) =>
                        const Icon(Icons.broken_image_outlined, size: 48),
                  ),
                ),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.file(
                media.resolve(image.thumbPath),
                fit: BoxFit.cover,
                cacheWidth: (size * 3).round(),
                errorBuilder: (_, _, _) => ColoredBox(
                  color: scheme.surfaceContainerHighest,
                  child: const Icon(Icons.broken_image_outlined),
                ),
              ),
            ),
          ),
          if (onRemove != null)
            Positioned(
              top: 0,
              right: 0,
              child: InkWell(
                key: ValueKey('remove-${image.path}'),
                onTap: onRemove,
                child: Tooltip(
                  message: l10n.photoRemove,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: scheme.surface.withValues(alpha: 0.85),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close, size: 16),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Camera / gallery buttons.
class PhotoAddButtons extends StatelessWidget {
  const PhotoAddButtons({required this.onPick, this.keyPrefix = '', super.key});

  final ValueChanged<PhotoOrigin> onPick;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return Wrap(
      spacing: 8,
      children: [
        OutlinedButton.icon(
          key: ValueKey('${keyPrefix}photo-camera'),
          onPressed: () => onPick(PhotoOrigin.camera),
          icon: const Icon(Icons.photo_camera_outlined),
          label: Text(l10n.photoCamera),
        ),
        OutlinedButton.icon(
          key: ValueKey('${keyPrefix}photo-gallery'),
          onPressed: () => onPick(PhotoOrigin.gallery),
          icon: const Icon(Icons.photo_library_outlined),
          label: Text(l10n.photoGallery),
        ),
      ],
    );
  }
}

/// Photos of a garment that is still being added to a new order (O-3). Files
/// are saved at once; they are linked to the order when it is saved.
class DraftPhotosSection extends ConsumerWidget {
  const DraftPhotosSection({
    required this.item,
    required this.draft,
    super.key,
  });

  final DraftItem item;
  final OrderDraft draft;

  Future<void> _pick(
    BuildContext context,
    WidgetRef ref,
    PhotoOrigin origin,
  ) async {
    final l10n = AppL10n.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await ref.read(photoSourceProvider).pick(origin);
      if (bytes == null) return;
      final stored = await ref.read(mediaStoreProvider).saveImage(bytes);
      item.photos.add(stored);
      draft.changed();
    } on Object {
      messenger.showSnackBar(SnackBar(content: Text(l10n.photoFailed)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.photosTitle, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        if (item.photos.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final photo in item.photos)
                  PhotoThumb(
                    image: photo,
                    onRemove: () async {
                      item.photos.remove(photo);
                      draft.changed();
                      await ref.read(mediaStoreProvider).delete(photo);
                    },
                  ),
              ],
            ),
          ),
        PhotoAddButtons(
          keyPrefix: '${item.garment.key}-',
          onPick: (origin) => _pick(context, ref, origin),
        ),
      ],
    );
  }
}

/// Photos of a garment in a saved order (view, add, remove).
class ItemPhotosSection extends ConsumerWidget {
  const ItemPhotosSection({
    required this.itemId,
    required this.editable,
    super.key,
  });

  final String itemId;
  final bool editable;

  Future<void> _pick(
    BuildContext context,
    WidgetRef ref,
    PhotoOrigin origin,
  ) async {
    final l10n = AppL10n.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(attachmentRepositoryProvider)
          .addFromSource(
            ref.read(photoSourceProvider),
            origin,
            AttachmentOwner.orderItem,
            itemId,
          );
    } on Object {
      messenger.showSnackBar(SnackBar(content: Text(l10n.photoFailed)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photos = ref.watch(itemPhotosProvider(itemId)).value ?? const [];
    if (photos.isEmpty && !editable) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (photos.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final photo in photos)
                    PhotoThumb(
                      image: photo.image,
                      onRemove: editable
                          ? () => ref
                                .read(attachmentRepositoryProvider)
                                .remove(photo)
                          : null,
                    ),
                ],
              ),
            ),
          if (editable)
            PhotoAddButtons(
              keyPrefix: '$itemId-',
              onPick: (origin) => _pick(context, ref, origin),
            ),
        ],
      ),
    );
  }
}

/// Useful for tests and previews: does the file for [image] exist?
bool storedImageExists(MediaStore media, StoredImage image) =>
    File(media.resolve(image.path).path).existsSync();
