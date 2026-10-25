import 'package:flutter/material.dart';

class VirtualJoystick extends StatefulWidget {
  final Function(Offset offset) onJoystickChanged;
  const VirtualJoystick({super.key, required this.onJoystickChanged});

  @override
  State<VirtualJoystick> createState() => _VirtualJoystickState();
}

class _VirtualJoystickState extends State<VirtualJoystick> {
  Offset _dragPosition = Offset.zero;
  static const double _maxRadius = 45.0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanUpdate: (details) {
        setState(() {
          final newOffset = _dragPosition + details.delta;
          if (newOffset.distance <= _maxRadius) {
            _dragPosition = newOffset;
          } else {
            _dragPosition = newOffset / newOffset.distance * _maxRadius;
          }
        });
        widget.onJoystickChanged(_dragPosition / _maxRadius);
      },
      onPanEnd: (details) {
        setState(() {
          _dragPosition = Offset.zero;
        });
        widget.onJoystickChanged(Offset.zero);
      },
      child: Container(
        width: 110,
        height: 110,
        decoration: BoxDecoration(
          color: const Color(0x331E293B), // Sleek glass base
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0x66334155), width: 1.5),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 10,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Center(
          child: Transform.translate(
            offset: _dragPosition,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0F766E), Color(0xFF0D9488)], // primary brand accent
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xAAFFFFFF), width: 1.0),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black45,
                    blurRadius: 5,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(
                Icons.drag_indicator,
                color: Colors.white,
                size: 18,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
