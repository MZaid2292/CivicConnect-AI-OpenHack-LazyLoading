import 'package:flutter/material.dart';

import '../backend_mode.dart';
import '../models/media_attachment.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'civic_widgets.dart';

class PhotoTile extends StatelessWidget {
  const PhotoTile({
    super.key,
    required this.media,
    this.size = 120,
    this.onRemove,
    this.showCaption = true,
    this.showStorageLabel = true,
  });
  final MediaAttachment media;
  final double size;
  final VoidCallback? onRemove;
  final bool showCaption;
  final bool showStorageLabel;

  @override
  Widget build(BuildContext context) => Semantics(
        image: true,
        label: '${media.caption}. ${media.storageLabel}',
        child: SizedBox(
          width: size,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ClipRRect(
              borderRadius:
                  BorderRadius.circular(size < 90 ? Radii.sm : Radii.md),
              child: SizedBox.square(
                dimension: size,
                child: Stack(fit: StackFit.expand, children: [
                  MediaImage(media: media),
                  if (showStorageLabel)
                    Positioned(
                        left: 6, bottom: 6, right: 6, child: StorageTag(media)),
                  if (onRemove != null)
                    Positioned(
                      top: 2,
                      right: 2,
                      child: IconButton.filledTonal(
                        tooltip: 'Remove photo',
                        iconSize: 18,
                        onPressed: onRemove,
                        icon: const Icon(Icons.close),
                      ),
                    ),
                ]),
              ),
            ),
            if (showCaption)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(media.caption,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.textStyles.bodySmall
                        ?.copyWith(color: context.civic.muted)),
              ),
          ]),
        ),
      );
}

class MediaImage extends StatelessWidget {
  const MediaImage({super.key, required this.media});
  final MediaAttachment media;

  @override
  Widget build(BuildContext context) {
    if (media.bytes != null) {
      return Image.memory(media.bytes!,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => _Illustration(media: media));
    }
    if (media.remoteUrl != null) {
      return Image.network(media.remoteUrl!,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => _Illustration(media: media));
    }
    return _Illustration(media: media);
  }
}

class StorageTag extends StatelessWidget {
  const StorageTag(this.media, {super.key});
  final MediaAttachment media;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.bottomLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(Radii.pill)),
          child: Text(media.storageLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 10)),
        ),
      );
}

class _Illustration extends StatelessWidget {
  const _Illustration({required this.media});
  final MediaAttachment media;

  @override
  Widget build(BuildContext context) {
    final (icon, colors) = switch (media.stage) {
      EvidenceStage.after => (
          Icons.verified,
          const [Color(0xFF0F766E), Color(0xFF14B8A6)]
        ),
      EvidenceStage.before => (
          Icons.report_problem_outlined,
          const [Color(0xFF9A3412), Color(0xFFF97316)]
        ),
      EvidenceStage.progress => (
          Icons.construction,
          const [Color(0xFF92400E), Color(0xFFF59E0B)]
        ),
      EvidenceStage.report => (
          Icons.photo_camera_outlined,
          const [Color(0xFF0B1F4B), Color(0xFF1D4ED8)]
        ),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
          gradient: LinearGradient(
              colors: colors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight)),
      child: LayoutBuilder(
        builder: (context, c) => Center(
            child: Icon(icon,
                color: Colors.white70,
                size: (c.biggest.shortestSide * 0.35).clamp(16, 64))),
      ),
    );
  }
}

class PhotoStrip extends StatelessWidget {
  const PhotoStrip({super.key, required this.photos, this.size = 120});
  final List<MediaAttachment> photos;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: size + 44,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: photos.length,
          separatorBuilder: (_, __) => Space.gapMd,
          itemBuilder: (_, i) => PhotoTile(media: photos[i], size: size),
        ),
      );
}

class EvidenceGallery extends StatefulWidget {
  const EvidenceGallery({super.key, required this.photos, this.heroTag});
  final List<MediaAttachment> photos;

  final String? heroTag;

  @override
  State<EvidenceGallery> createState() => _EvidenceGalleryState();
}

class _EvidenceGalleryState extends State<EvidenceGallery> {
  final _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final photos = widget.photos;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ClipRRect(
        borderRadius: Radii.brLg,
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(fit: StackFit.expand, children: [
            PageView.builder(
              controller: _controller,
              itemCount: photos.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (_, i) {
                final image = Semantics(
                    image: true,
                    label: photos[i].caption,
                    child: MediaImage(media: photos[i]));
                return i == 0 && widget.heroTag != null
                    ? Hero(tag: widget.heroTag!, child: image)
                    : image;
              },
            ),
            Positioned(
              left: Space.md,
              right: Space.md,
              bottom: Space.md,
              child: Row(children: [
                Flexible(child: StorageTag(photos[_index])),
                const Spacer(),
                if (photos.length > 1)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(Radii.pill)),
                    child: Text('${_index + 1}/${photos.length}',
                        style:
                            const TextStyle(color: Colors.white, fontSize: 12)),
                  ),
              ]),
            ),
          ]),
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(top: Space.sm),
        child: Text(photos[_index].caption,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: context.textStyles.bodySmall
                ?.copyWith(color: context.civic.muted)),
      ),
      if (photos.length > 1)
        SizedBox(
          height: 64,
          child: ListView.separated(
            padding: const EdgeInsets.only(top: Space.sm),
            scrollDirection: Axis.horizontal,
            itemCount: photos.length,
            separatorBuilder: (_, __) => Space.gapSm,
            itemBuilder: (_, i) => GestureDetector(
              onTap: () => _controller.animateToPage(i,
                  duration: Motion.of(context, Motion.medium),
                  curve: Motion.curve),
              child: AnimatedContainer(
                duration: Motion.of(context, Motion.fast),
                width: 56,
                decoration: BoxDecoration(
                  borderRadius: Radii.brSm,
                  border: Border.all(
                      color: i == _index
                          ? context.colors.primary
                          : Colors.transparent,
                      width: 2),
                ),
                child: ClipRRect(
                    borderRadius: BorderRadius.circular(Radii.sm - 2),
                    child: MediaImage(media: photos[i])),
              ),
            ),
          ),
        ),
    ]);
  }
}

class CivicImagePickerCard extends StatelessWidget {
  const CivicImagePickerCard({
    super.key,
    required this.photos,
    required this.onAdd,
    this.onRemove,
    this.maxPhotos = 4,
    this.title = 'Add photos',
    this.subtitle = 'A clear photo helps crews find and verify the issue.',
  });
  final List<MediaAttachment> photos;
  final VoidCallback onAdd;
  final void Function(String id)? onRemove;
  final int maxPhotos;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final civic = context.civic;
    final canAdd = photos.length < maxPhotos;
    if (photos.isEmpty) {
      return Semantics(
        button: true,
        label: title,
        child: InkWell(
          onTap: onAdd,
          borderRadius: Radii.brLg,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
                horizontal: Space.lg, vertical: Space.xl),
            decoration: BoxDecoration(
              color: context.colors.surfaceContainerLow,
              borderRadius: Radii.brLg,
              border: Border.all(
                  color: context.colors.primary.withValues(alpha: 0.35),
                  width: 1.5),
            ),
            child: Column(children: [
              CivicIconBadge(icon: Icons.add_a_photo_outlined, size: 52),
              Space.gapMd,
              Text(title, style: context.textStyles.titleSmall),
              Space.gapXs,
              Text(subtitle,
                  textAlign: TextAlign.center,
                  style: context.textStyles.bodySmall
                      ?.copyWith(color: civic.muted)),
              Space.gapXs,
              Text(
                  context.isLiveBackend
                      ? 'Up to $maxPhotos · uploaded privately when you submit'
                      : 'Up to $maxPhotos · stays on this device (demo)',
                  textAlign: TextAlign.center,
                  style: context.textStyles.labelSmall
                      ?.copyWith(color: civic.subtle)),
            ]),
          ),
        ),
      );
    }
    return Wrap(spacing: Space.md, runSpacing: Space.md, children: [
      for (final p in photos)
        PhotoTile(
            media: p,
            size: 96,
            showCaption: false,
            onRemove: onRemove == null ? null : () => onRemove!(p.id)),
      if (canAdd)
        Semantics(
          button: true,
          label: 'Add another photo',
          child: InkWell(
            onTap: onAdd,
            borderRadius: Radii.brMd,
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                borderRadius: Radii.brMd,
                color: context.colors.surfaceContainerLow,
                border: Border.all(color: civic.border, width: 1.5),
              ),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_photo_alternate_outlined,
                        color: context.colors.primary),
                    const SizedBox(height: 4),
                    Text('${photos.length}/$maxPhotos',
                        style: context.textStyles.labelSmall
                            ?.copyWith(color: civic.muted)),
                  ]),
            ),
          ),
        ),
    ]);
  }
}

Future<bool?> askCameraOrGallery(BuildContext context,
        {bool allowGallery = true}) =>
    showModalBottomSheet<bool>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Take a photo'),
            onTap: () => Navigator.pop(context, true),
          ),
          if (allowGallery)
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(context, false),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
                Space.lg, Space.xs, Space.lg, Space.lg),
            child: Text(
              context.isLiveBackend
                  ? 'Photos are uploaded to private storage when you submit '
                      'and are visible only to signed-in users.'
                  : 'Demo: photos stay in this device\'s memory only and are '
                      'not uploaded. They disappear when the app restarts.',
              style: context.textStyles.bodySmall
                  ?.copyWith(color: context.civic.muted),
            ),
          ),
        ]),
      ),
    );
