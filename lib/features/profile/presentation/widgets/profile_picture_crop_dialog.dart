import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image/image.dart' as img;

import '../../../auth/presentation/widgets/auth_components.dart';

/// WhatsApp / Instagram style circular profile picture crop dialog.
/// Displays an interactive circular viewport where users can pan and pinch/slider zoom
/// their selected image with a circular mask preview before generating the final crop.
class ProfilePictureCropDialog extends StatefulWidget {
  final Uint8List rawImageBytes;

  const ProfilePictureCropDialog({
    super.key,
    required this.rawImageBytes,
  });

  /// Opens the interactive cropping dialog and returns the cropped square JPEG bytes,
  /// or null if the user cancelled.
  static Future<Uint8List?> show(BuildContext context, Uint8List rawBytes) {
    return showDialog<Uint8List>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ProfilePictureCropDialog(rawImageBytes: rawBytes),
    );
  }

  @override
  State<ProfilePictureCropDialog> createState() => _ProfilePictureCropDialogState();
}

class _ProfilePictureCropDialogState extends State<ProfilePictureCropDialog> {
  final TransformationController _transformController = TransformationController();
  
  img.Image? _decodedImage;
  bool _isDecoding = true;
  bool _isProcessing = false;
  String? _errorMessage;

  double _currentZoom = 1.0;
  static const double _minZoom = 1.0;
  static const double _maxZoom = 3.5;

  // Viewport dimensions (square)
  double _viewportSize = 300.0;
  double _layoutWidth = 300.0;
  double _layoutHeight = 300.0;

  @override
  void initState() {
    super.initState();
    _decodeImage();
    _transformController.addListener(_onTransformChanged);
  }

  @override
  void dispose() {
    _transformController.removeListener(_onTransformChanged);
    _transformController.dispose();
    super.dispose();
  }

  void _onTransformChanged() {
    final matrix = _transformController.value;
    final scale = matrix.getMaxScaleOnAxis();
    if ((scale - _currentZoom).abs() > 0.02 && mounted) {
      setState(() {
        _currentZoom = scale.clamp(_minZoom, _maxZoom);
      });
    }
  }

  Future<void> _decodeImage() async {
    setState(() {
      _isDecoding = true;
      _errorMessage = null;
    });

    try {
      final decoded = _decodeAndOrient(widget.rawImageBytes);
      if (decoded == null) {
        if (mounted) {
          setState(() {
            _isDecoding = false;
            _errorMessage = 'Unable to decode the selected image. Please choose another file.';
          });
        }
        return;
      }

      if (mounted) {
        setState(() {
          _decodedImage = decoded;
          _isDecoding = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDecoding = false;
          _errorMessage = 'Failed to load image: ${e.toString()}';
        });
      }
    }
  }

  void _calculateLayout(double viewportSize) {
    if (_decodedImage == null) return;
    _viewportSize = viewportSize;

    final imgW = _decodedImage!.width.toDouble();
    final imgH = _decodedImage!.height.toDouble();

    // Scale image so its shorter dimension exactly fills the circular viewport at 1.0x
    final scale = viewportSize / min(imgW, imgH);
    _layoutWidth = imgW * scale;
    _layoutHeight = imgH * scale;

    // Center the image initially inside the viewport
    final initialTx = (viewportSize - _layoutWidth) / 2;
    final initialTy = (viewportSize - _layoutHeight) / 2;

    _transformController.value = _buildMatrix(initialTx, initialTy, 1.0);
  }

  Matrix4 _buildMatrix(double tx, double ty, double scale) {
    return Matrix4.identity()
      ..setEntry(0, 0, scale)
      ..setEntry(1, 1, scale)
      ..setEntry(0, 3, tx)
      ..setEntry(1, 3, ty);
  }

  void _setZoom(double zoom) {
    zoom = zoom.clamp(_minZoom, _maxZoom);
    final matrix = _transformController.value;
    final oldScale = matrix.getMaxScaleOnAxis();
    if (oldScale <= 0) return;

    final scaleFactor = zoom / oldScale;

    // Zoom relative to the center of the viewport
    final center = Offset(_viewportSize / 2, _viewportSize / 2);
    final currentTx = matrix.storage[12];
    final currentTy = matrix.storage[13];

    final newTx = center.dx - (center.dx - currentTx) * scaleFactor;
    final newTy = center.dy - (center.dy - currentTy) * scaleFactor;

    _transformController.value = _buildMatrix(newTx, newTy, zoom);

    setState(() {
      _currentZoom = zoom;
    });
  }

  void _resetTransform() {
    _setZoom(1.0);
    final initialTx = (_viewportSize - _layoutWidth) / 2;
    final initialTy = (_viewportSize - _layoutHeight) / 2;
    _transformController.value = _buildMatrix(initialTx, initialTy, 1.0);
  }

  Future<void> _handleSave() async {
    if (_decodedImage == null || _isProcessing) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      final matrix = _transformController.value;
      final scale = matrix.getMaxScaleOnAxis();
      final tx = matrix.storage[12];
      final ty = matrix.storage[13];

      final cropParams = _CropParameters(
        imageBytes: widget.rawImageBytes,
        viewportSize: _viewportSize,
        layoutWidth: _layoutWidth,
        layoutHeight: _layoutHeight,
        scale: scale,
        tx: tx,
        ty: ty,
        targetResolution: 512,
      );

      final croppedBytes = _executeCrop(cropParams);

      if (mounted) {
        Navigator.of(context).pop(croppedBytes);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _errorMessage = 'Failed to crop image: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final screenWidth = media.size.width;
    final screenHeight = media.size.height;
    final isDesktop = screenWidth >= 700;

    final availableWidth = screenWidth - (isDesktop ? 160 : 48);
    final availableHeight = screenHeight - (isDesktop ? 220 : 180);
    final targetViewportSize = min(min(availableWidth, availableHeight), 360.0).clamp(240.0, 360.0);

    return Dialog(
      backgroundColor: AuthPalette.cardSurface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AuthPalette.cardBorder, width: 1),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: isDesktop ? 460 : 380,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header title & instruction
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Crop Profile Picture',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AuthPalette.textPrimary,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20, color: AuthPalette.textMuted),
                    onPressed: _isProcessing ? null : () => Navigator.of(context).pop(null),
                    tooltip: 'Cancel',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Drag to reposition and zoom to adjust your photo.',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12.5,
                  color: AuthPalette.textMuted,
                ),
              ),
              const SizedBox(height: 16),

              // Error banner if any
              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AuthPalette.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AuthPalette.errorRed.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      color: AuthPalette.errorRed,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Central Crop Viewport
              Center(
                child: SizedBox(
                  width: targetViewportSize,
                  height: targetViewportSize,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      color: const Color(0xFF140D0F),
                      child: _isDecoding
                          ? const Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: AuthPalette.primaryButton,
                              ),
                            )
                          : LayoutBuilder(
                              builder: (ctx, constraints) {
                                if (_viewportSize != targetViewportSize) {
                                  WidgetsBinding.instance.addPostFrameCallback((_) {
                                    if (mounted) _calculateLayout(targetViewportSize);
                                  });
                                }

                                return Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    // Interactive image viewer
                                    InteractiveViewer(
                                      transformationController: _transformController,
                                      minScale: _minZoom,
                                      maxScale: _maxZoom,
                                      panEnabled: true,
                                      scaleEnabled: true,
                                      clipBehavior: Clip.none,
                                      boundaryMargin: EdgeInsets.all(targetViewportSize * 0.4),
                                      child: SizedBox(
                                        width: _layoutWidth,
                                        height: _layoutHeight,
                                        child: Image.memory(
                                          widget.rawImageBytes,
                                          fit: BoxFit.fill,
                                          filterQuality: FilterQuality.medium,
                                        ),
                                      ),
                                    ),

                                    // Circular mask overlay with darkened edges
                                    IgnorePointer(
                                      child: CustomPaint(
                                        size: Size(targetViewportSize, targetViewportSize),
                                        painter: _CircularHoleMaskPainter(
                                          holeRadius: targetViewportSize * 0.46,
                                          borderColor: Colors.white.withValues(alpha: 0.85),
                                          maskColor: const Color(0x991A0F12),
                                        ),
                                      ),
                                    ),

                                    // Loading state overlay when generating crop
                                    if (_isProcessing)
                                      Container(
                                        color: Colors.black45,
                                        child: Center(
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const CircularProgressIndicator(
                                                color: Colors.white,
                                                strokeWidth: 3,
                                              ),
                                              const SizedBox(height: 12),
                                              Text(
                                                'Saving crop...',
                                                style: GoogleFonts.plusJakartaSans(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                  ],
                                );
                              },
                            ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Zoom slider and zoom quick controls
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline, size: 20),
                    color: AuthPalette.textMuted,
                    onPressed: _isProcessing
                        ? null
                        : () => _setZoom(_currentZoom - 0.25),
                    tooltip: 'Zoom out',
                  ),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: AuthPalette.primaryButton,
                        inactiveTrackColor: AuthPalette.cardBorder,
                        thumbColor: AuthPalette.primaryButton,
                        overlayColor: AuthPalette.primaryButton.withValues(alpha: 0.15),
                        trackHeight: 3,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                      ),
                      child: Slider(
                        value: _currentZoom.clamp(_minZoom, _maxZoom),
                        min: _minZoom,
                        max: _maxZoom,
                        onChanged: _isProcessing ? null : (v) => _setZoom(v),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline, size: 20),
                    color: AuthPalette.textMuted,
                    onPressed: _isProcessing
                        ? null
                        : () => _setZoom(_currentZoom + 0.25),
                    tooltip: 'Zoom in',
                  ),
                  IconButton(
                    icon: const Icon(Icons.restart_alt_rounded, size: 20),
                    color: AuthPalette.textMuted,
                    onPressed: _isProcessing ? null : _resetTransform,
                    tooltip: 'Reset view',
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Action buttons (Cancel / Save)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isProcessing ? null : () => Navigator.of(context).pop(null),
                    style: TextButton.styleFrom(
                      foregroundColor: AuthPalette.textMuted,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                    child: Text(
                      'Cancel',
                      style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: (_isDecoding || _isProcessing || _decodedImage == null)
                        ? null
                        : _handleSave,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AuthPalette.primaryButton,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: _isProcessing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            'Save Photo',
                            style: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Custom painter that dims the surrounding area and leaves a transparent circular hole
/// with a crisp white alignment ring.
class _CircularHoleMaskPainter extends CustomPainter {
  final double holeRadius;
  final Color borderColor;
  final Color maskColor;

  _CircularHoleMaskPainter({
    required this.holeRadius,
    required this.borderColor,
    required this.maskColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // 1. Create transparent circular cutout via Difference path operation
    final fullRect = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final circleHole = Path()
      ..addOval(Rect.fromCircle(center: center, radius: holeRadius));
    final maskPath = Path.combine(PathOperation.difference, fullRect, circleHole);

    final maskPaint = Paint()
      ..color = maskColor
      ..style = PaintingStyle.fill;
    canvas.drawPath(maskPath, maskPaint);

    // 2. Draw circular guide border
    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(center, holeRadius, borderPaint);

    // 3. Optional subtle dashed/crosshair center guide
    final guidePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawLine(Offset(center.dx - 10, center.dy), Offset(center.dx + 10, center.dy), guidePaint);
    canvas.drawLine(Offset(center.dx, center.dy - 10), Offset(center.dx, center.dy + 10), guidePaint);
  }

  @override
  bool shouldRepaint(covariant _CircularHoleMaskPainter oldDelegate) {
    return oldDelegate.holeRadius != holeRadius ||
        oldDelegate.borderColor != borderColor ||
        oldDelegate.maskColor != maskColor;
  }
}

/// Parameters passed to background compute isolate to execute the mathematical crop
class _CropParameters {
  final Uint8List imageBytes;
  final double viewportSize;
  final double layoutWidth;
  final double layoutHeight;
  final double scale;
  final double tx;
  final double ty;
  final int targetResolution;

  _CropParameters({
    required this.imageBytes,
    required this.viewportSize,
    required this.layoutWidth,
    required this.layoutHeight,
    required this.scale,
    required this.tx,
    required this.ty,
    required this.targetResolution,
  });
}

/// Decodes and normalizes EXIF orientation
img.Image? _decodeAndOrient(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  return img.bakeOrientation(decoded);
}

/// Computes the exact pixel crop from transformation matrix and returns encoded JPEG bytes
Uint8List _executeCrop(_CropParameters params) {
  var image = img.decodeImage(params.imageBytes);
  if (image == null) throw Exception('Unable to decode image bytes for crop.');
  image = img.bakeOrientation(image);

  final imgW = image.width.toDouble();
  final imgH = image.height.toDouble();

  // The circular viewport covers [0, 0] to [viewportSize, viewportSize]
  // Invert transformation: point in layout coordinates is (x_viewport - tx) / scale
  // Layout coordinates to image pixel factor: imgW / layoutWidth
  final xRatio = imgW / params.layoutWidth;
  final yRatio = imgH / params.layoutHeight;

  final cropXInLayout = (0.0 - params.tx) / params.scale;
  final cropYInLayout = (0.0 - params.ty) / params.scale;
  final cropWInLayout = params.viewportSize / params.scale;
  final cropHInLayout = params.viewportSize / params.scale;

  // Convert to image pixels
  var cropX = (cropXInLayout * xRatio).round();
  var cropY = (cropYInLayout * yRatio).round();
  var cropW = (cropWInLayout * xRatio).round();
  var cropH = (cropHInLayout * yRatio).round();

  // Enforce square aspect ratio
  final squareSize = min(cropW, cropH);
  cropW = squareSize;
  cropH = squareSize;

  // Clamp safely within source bounds
  if (cropX < 0) cropX = 0;
  if (cropY < 0) cropY = 0;
  if (cropX + cropW > image.width) {
    cropW = image.width - cropX;
  }
  if (cropY + cropH > image.height) {
    cropH = image.height - cropY;
  }

  // Minimum valid crop dimension guard
  if (cropW <= 0 || cropH <= 0) {
    final side = min(image.width, image.height);
    cropX = (image.width - side) ~/ 2;
    cropY = (image.height - side) ~/ 2;
    cropW = side;
    cropH = side;
  }

  // Crop square region
  final cropped = img.copyCrop(
    image,
    x: cropX,
    y: cropY,
    width: cropW,
    height: cropH,
  );

  // Resize to standard avatar resolution (512x512)
  final resized = img.copyResize(
    cropped,
    width: params.targetResolution,
    height: params.targetResolution,
    interpolation: img.Interpolation.linear,
  );

  // Encode to high-quality JPEG
  return Uint8List.fromList(img.encodeJpg(resized, quality: 88));
}
