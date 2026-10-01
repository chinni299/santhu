import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'shared_sky_model.dart';
import 'shared_sky_painter.dart';
import 'shared_sky_service.dart';

class SharedSkyScreen extends StatefulWidget {
  final int conversationId;
  final int currentUserId;
  final String partnerName;
  final io.Socket? socket;

  const SharedSkyScreen({
    super.key,
    required this.conversationId,
    required this.currentUserId,
    this.partnerName = 'Partner',
    this.socket,
  });

  @override
  State<SharedSkyScreen> createState() => _SharedSkyScreenState();
}

class _SharedSkyScreenState extends State<SharedSkyScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  final List<CelestialStar> _stars = SkyGenerator.generateStars();
  final Map<int, NamedStar> _namedStars = {};

  int? _selectedStarIndex;
  int? _partnerHoverStarIndex;
  bool _partnerIsHere = false;
  bool _isLoading = true;

  final List<ShootingStar> _shootingStars = [];
  Timer? _shootingStarTimer;
  final Random _rng = Random();

  @override
  void initState() {
    super.initState();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();

    _animController.addListener(_updatePhysics);

    _initService();
    _loadStars();
    _startShootingStarSpawner();
  }

  void _initService() {
    SharedSkyService.initialize(widget.socket, widget.conversationId);

    SharedSkyService.onStarNamed = (star) {
      if (mounted) {
        setState(() {
          _namedStars[star.starIndex] = star;
        });
        _showNotificationToast('✨ New Star: "${star.starName}" named!');
      }
    };

    SharedSkyService.onStarUpdated = (star) {
      if (mounted) {
        setState(() {
          _namedStars[star.starIndex] = star;
        });
      }
    };

    SharedSkyService.onStarDeleted = (starIndex, starId) {
      if (mounted) {
        setState(() {
          _namedStars.remove(starIndex);
          if (_selectedStarIndex == starIndex) {
            _selectedStarIndex = null;
          }
        });
      }
    };

    SharedSkyService.onPartnerHover = (starIndex, isHovering, userId) {
      if (mounted) {
        setState(() {
          _partnerHoverStarIndex = isHovering ? starIndex : null;
        });
      }
    };

    SharedSkyService.onPartnerStatus = (isOpen, userId) {
      if (mounted) {
        setState(() {
          _partnerIsHere = isOpen;
        });
        if (isOpen) {
          _showNotificationToast('🌌 ${widget.partnerName} joined Our Sky!');
        }
      }
    };

    SharedSkyService.openSky();
  }

  Future<void> _loadStars() async {
    final stars = await SharedSkyService.fetchStars(widget.conversationId);
    if (mounted) {
      setState(() {
        for (final s in stars) {
          _namedStars[s.starIndex] = s;
        }
        _isLoading = false;
      });
    }
  }

  void _startShootingStarSpawner() {
    // Spawn a shooting star every 4 to 8 seconds randomly
    void scheduleNext() {
      final delay = 3000 + _rng.nextInt(4500);
      _shootingStarTimer = Timer(Duration(milliseconds: delay), () {
        if (!mounted) return;
        _spawnShootingStar();
        scheduleNext();
      });
    }

    scheduleNext();
  }

  void _spawnShootingStar() {
    // Generate random diagonal trajectory
    final startX = 0.1 + _rng.nextDouble() * 0.7;
    final startY = 0.05 + _rng.nextDouble() * 0.3;
    final angle = pi / 4 + (_rng.nextDouble() - 0.5) * (pi / 6);
    final distance = 0.35 + _rng.nextDouble() * 0.35;

    final endX = (startX + cos(angle) * distance).clamp(0.0, 1.0);
    final endY = (startY + sin(angle) * distance).clamp(0.0, 1.0);

    final colors = [
      const Color(0xFF64B5F6),
      const Color(0xFFFF80AB),
      const Color(0xFFFFD54F),
      const Color(0xFFE040FB),
      Colors.white,
    ];

    final star = ShootingStar(
      startX: startX,
      startY: startY,
      endX: endX,
      endY: endY,
      progress: 0.0,
      speed: 0.012 + _rng.nextDouble() * 0.014,
      length: 0.18 + _rng.nextDouble() * 0.12,
      color: colors[_rng.nextInt(colors.length)],
    );

    _shootingStars.add(star);
  }

  void _updatePhysics() {
    // Advance shooting star progress
    for (int i = _shootingStars.length - 1; i >= 0; i--) {
      final s = _shootingStars[i];
      s.progress += s.speed;
      if (s.progress >= 1.0 + s.length) {
        _shootingStars.removeAt(i);
      }
    }
  }

  void _showNotificationToast(String msg) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        backgroundColor: const Color(0xE61E1B4B),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  void dispose() {
    SharedSkyService.closeSky();
    _shootingStarTimer?.cancel();
    _animController.dispose();
    super.dispose();
  }

  // ── Star Touch & Hit Detection ──────────────────────────────────────────

  void _handleTapDown(TapDownDetails details, Size size) {
    final localPos = details.localPosition;
    final touchX = localPos.dx / size.width;
    final touchY = localPos.dy / size.height;

    // Find closest star within 32 logical pixels threshold
    int? closestIdx;
    double closestDistSq = double.infinity;
    const maxThresholdPx = 32.0;
    final maxThresholdDistSq = pow(maxThresholdPx / size.width, 2) +
        pow(maxThresholdPx / size.height, 2);

    for (final star in _stars) {
      final dx = star.x - touchX;
      final dy = star.y - touchY;
      final distSq = dx * dx + dy * dy;

      if (distSq < closestDistSq && distSq < maxThresholdDistSq) {
        closestDistSq = distSq;
        closestIdx = star.index;
      }
    }

    if (closestIdx != null) {
      setState(() => _selectedStarIndex = closestIdx);
      SharedSkyService.emitHover(closestIdx, true);

      final named = _namedStars[closestIdx];
      if (named != null) {
        _showNamedStarDetails(named);
      } else {
        _showNameStarDialog(closestIdx);
      }
    }
  }

  // ── Dialogs & Bottom Sheets ──────────────────────────────────────────────

  void _showNameStarDialog(int starIndex) {
    final controller = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            top: 20,
            left: 24,
            right: 24,
          ),
          decoration: const BoxDecoration(
            color: Color(0xFF0F172A),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(
              top: BorderSide(color: Color(0x55FFD700), width: 1.5),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: const [
                  Text('🌟', style: TextStyle(fontSize: 24)),
                  SizedBox(width: 10),
                  Text(
                    'Name this Star',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Give this celestial star a special memory or meaningful name for both of you.',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 13.5),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: controller,
                autofocus: true,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                decoration: InputDecoration(
                  hintText: 'e.g. Our First Date, Under The Moonlight...',
                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
                  filled: true,
                  fillColor: const Color(0xFF1E293B),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: Color(0x44FFD700)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: Color(0xFFFFD700), width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text(
                        'Cancel',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 15),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        final text = controller.text.trim();
                        if (text.isEmpty) return;
                        Navigator.pop(ctx);
                        _performNameStar(starIndex, text);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFFB703),
                        foregroundColor: const Color(0xFF0F172A),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 4,
                      ),
                      child: const Text(
                        'Claim Star ✨',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _performNameStar(int starIndex, String name) async {
    final newStar = await SharedSkyService.nameStar(
      conversationId: widget.conversationId,
      starIndex: starIndex,
      starName: name,
    );

    if (newStar != null) {
      setState(() {
        _namedStars[starIndex] = newStar;
      });
      _showNotificationToast('🌟 "$name" has been placed into your sky forever!');
    } else {
      _showNotificationToast('⚠️ Could not name star. Try another star.');
    }
  }

  void _showNamedStarDetails(NamedStar star) {
    final isMyStar = star.namedByUserId == widget.currentUserId;
    final dateStr =
        '${star.createdAt.day}/${star.createdAt.month}/${star.createdAt.year}';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 30),
          decoration: const BoxDecoration(
            color: Color(0xFF0B1120),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(
              top: BorderSide(color: Color(0xFFFFD700), width: 1.5),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFFFD700).withValues(alpha: 0.12),
                  border: Border.all(color: const Color(0xFFFFD700), width: 1.5),
                ),
                child: const Text('✨', style: TextStyle(fontSize: 32)),
              ),
              const SizedBox(height: 14),
              Text(
                star.starName,
                style: const TextStyle(
                  color: Color(0xFFFFF7D6),
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isMyStar ? Icons.person : Icons.favorite,
                    size: 14,
                    color: isMyStar ? const Color(0xFF60A5FA) : const Color(0xFFF472B6),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isMyStar
                        ? 'Named by You'
                        : 'Named by ${star.namedByUserName ?? widget.partnerName}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Text(' • ', style: TextStyle(color: Colors.white38)),
                  Text(
                    dateStr,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 13),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              if (isMyStar)
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _confirmDeleteStar(star);
                        },
                        icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFEF4444)),
                        label: const Text('Release Star', style: TextStyle(color: Color(0xFFEF4444))),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0x55EF4444)),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _showRenameStarDialog(star);
                        },
                        icon: const Icon(Icons.edit, size: 18),
                        label: const Text('Rename'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF3B82F6),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                  ],
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0x33EC4899),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0x55EC4899)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.auto_awesome, color: Color(0xFFF472B6), size: 18),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'A star dedicated with love by ${widget.partnerName} 💖',
                          style: const TextStyle(
                            color: Color(0xFFFCE7F3),
                            fontSize: 13.5,
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _showRenameStarDialog(NamedStar star) {
    final controller = TextEditingController(text: star.starName);
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0F172A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0x44FFD700)),
          ),
          title: const Text('Rename Star', style: TextStyle(color: Colors.white)),
          content: TextField(
            controller: controller,
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFF1E293B),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
            ),
            ElevatedButton(
              onPressed: () async {
                final newName = controller.text.trim();
                if (newName.isEmpty) return;
                Navigator.pop(ctx);
                final updated = await SharedSkyService.renameStar(
                  starId: star.id,
                  starName: newName,
                );
                if (updated != null && mounted) {
                  setState(() {
                    _namedStars[star.starIndex] = updated;
                  });
                  _showNotificationToast('✨ Star renamed to "$newName"');
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFB703)),
              child: const Text('Save', style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  void _confirmDeleteStar(NamedStar star) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0F172A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0x44EF4444)),
          ),
          title: const Text('Release Star?', style: TextStyle(color: Colors.white)),
          content: Text(
            'Are you sure you want to release "${star.starName}" back to the cosmos?',
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Keep Star', style: TextStyle(color: Colors.white60)),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                final success = await SharedSkyService.deleteStar(star.id);
                if (success && mounted) {
                  setState(() {
                    _namedStars.remove(star.starIndex);
                    if (_selectedStarIndex == star.starIndex) {
                      _selectedStarIndex = null;
                    }
                  });
                  _showNotificationToast('💫 Star released back to the cosmos.');
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
              child: const Text('Release', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  void _showStarCatalog() {
    final list = _namedStars.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          height: MediaQuery.of(ctx).size.height * 0.65,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          decoration: const BoxDecoration(
            color: Color(0xFF0B1120),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(top: BorderSide(color: Color(0x44FFD700))),
          ),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '🌌 Our Star Registry',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0x33FFD700),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${list.length} Named',
                      style: const TextStyle(
                        color: Color(0xFFFFD700),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Expanded(
                child: list.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('🔭', style: TextStyle(fontSize: 40)),
                            const SizedBox(height: 12),
                            Text(
                              'No stars named yet',
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 16),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Tap any twinkling star in the sky to name it together!',
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 13),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: list.length,
                        itemBuilder: (ctx, i) {
                          final item = list[i];
                          final isMe = item.namedByUserId == widget.currentUserId;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E293B).withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isMe
                                    ? const Color(0x3360A5FA)
                                    : const Color(0x33F472B6),
                              ),
                            ),
                            child: ListTile(
                              leading: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: const Color(0xFFFFD700).withValues(alpha: 0.15),
                                ),
                                child: const Text('✨', style: TextStyle(fontSize: 18)),
                              ),
                              title: Text(
                                item.starName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                              ),
                              subtitle: Text(
                                isMe ? 'By You' : 'By ${item.namedByUserName ?? widget.partnerName}',
                                style: TextStyle(
                                  color: isMe
                                      ? const Color(0xFF93C5FD)
                                      : const Color(0xFFF9A8D4),
                                  fontSize: 12.5,
                                ),
                              ),
                              trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.white38),
                              onTap: () {
                                Navigator.pop(ctx);
                                setState(() => _selectedStarIndex = item.starIndex);
                                _showNamedStarDetails(item);
                              },
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF030511),
      body: Stack(
        children: [
          // ── Astronomical Star Canvas ──────────────────────────────────────
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = Size(constraints.maxWidth, constraints.maxHeight);
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (details) => _handleTapDown(details, size),
                  child: AnimatedBuilder(
                    animation: _animController,
                    builder: (context, child) {
                      return CustomPaint(
                        size: size,
                        painter: SharedSkyPainter(
                          stars: _stars,
                          namedStars: _namedStars,
                          selectedStarIndex: _selectedStarIndex,
                          partnerHoverStarIndex: _partnerHoverStarIndex,
                          partnerIsHere: _partnerIsHere,
                          animationValue: _animController.value * 2 * pi,
                          shootingStars: _shootingStars,
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),

          // ── Top Glass Navigation & Presence Bar ───────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    // Back Button
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0x880F172A),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Title & Star Counter
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: const [
                              Text(
                                'Our Sky',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              SizedBox(width: 6),
                              Text('🌌', style: TextStyle(fontSize: 16)),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${_namedStars.length} Stars Named Together',
                            style: TextStyle(
                              color: const Color(0xFFFFD700).withValues(alpha: 0.9),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Star Registry Catalog Button
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0x880F172A),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0x44FFD700)),
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.auto_stories, color: Color(0xFFFFD700)),
                        tooltip: 'Star Registry',
                        onPressed: _showStarCatalog,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Partner Presence Banner ───────────────────────────────────────
          if (_partnerIsHere)
            Positioned(
              top: 76,
              left: 20,
              right: 20,
              child: SafeArea(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xCC0F172A),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0x88EC4899)),
                    boxShadow: const [
                      BoxShadow(color: Color(0x33EC4899), blurRadius: 12, spreadRadius: 1),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Color(0xFF10B981),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(color: Color(0xFF10B981), blurRadius: 6, spreadRadius: 2),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          '${widget.partnerName} is stargazing with you live ✨',
                          style: const TextStyle(
                            color: Color(0xFFFCE7F3),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // ── Bottom Instruction Helper ────────────────────────────────────
          Positioned(
            bottom: 24,
            left: 24,
            right: 24,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0x880B1120),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.touch_app, size: 16, color: Color(0xFFFFD700)),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Tap any star in the sky to name it or view memories',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.75),
                          fontSize: 12.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Loading Overlay ───────────────────────────────────────────────
          if (_isLoading)
            Positioned.fill(
              child: Container(
                color: const Color(0xCC030511),
                child: const Center(
                  child: CircularProgressIndicator(
                    color: Color(0xFFFFD700),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
