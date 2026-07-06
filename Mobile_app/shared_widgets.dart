import 'package:flutter/material.dart';

class NeumorphicContainer extends StatelessWidget {
  final Widget child;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final double borderRadius;
  final bool isInset;
  final Color backgroundColor;

  const NeumorphicContainer({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.padding,
    this.borderRadius = 20,
    this.isInset = false,
    this.backgroundColor = const Color(0xFFF7F9FC),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: isInset
            ? [
                const BoxShadow(
                  color: Colors.white,
                  offset: Offset(-4, -4),
                  blurRadius: 8,
                ),
                BoxShadow(
                  color: const Color(0xFFD8DADD).withValues(alpha: 0.8),
                  offset: const Offset(4, 4),
                  blurRadius: 8,
                ),
              ]
            : [
                const BoxShadow(
                  color: Colors.white,
                  offset: Offset(-8, -8),
                  blurRadius: 16,
                ),
                BoxShadow(
                  color: const Color(0xFFD8DADD).withValues(alpha: 0.8),
                  offset: const Offset(8, 8),
                  blurRadius: 16,
                ),
              ],
      ),
      child: child,
    );
  }
}

class GlobalHeader extends StatelessWidget {
  final String title;
  const GlobalHeader({super.key, this.title = 'SmartHome'});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // const NeumorphicContainer(
          //   padding: EdgeInsets.all(10),
          //   borderRadius: 12,
          //   child: Icon(Icons.menu, color: Color(0xFF003566)),
          // ),
          Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF3A86FF),
            ),
          ),
          // CircleAvatar(
          //   radius: 20,
          //   backgroundImage: NetworkImage(
          //     'https://images.unsplash.com/photo-1544005313-94ddf0286df2?auto=format&fit=crop&q=80&w=100',
          //   ),
          // ),
        ],
      ),
    );
  }
}

class NeumorphicBottomBar extends StatelessWidget {
  final int selectedIndex;
  final Function(int) onItemSelected;

  const NeumorphicBottomBar({
    super.key,
    required this.selectedIndex,
    required this.onItemSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(bottom: 24, top: 12, left: 24, right: 24),
      decoration: const BoxDecoration(color: Color(0xFFF7F9FC)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildItem(0, Icons.home_outlined, 'Home'),
          _buildItem(1, Icons.bar_chart_rounded, 'Stats'),
          _buildItem(2, Icons.bolt, 'Power'),
          _buildItem(3, Icons.analytics_outlined, 'Analytics'),
          _buildItem(4, Icons.settings_outlined, 'Settings'),
        ],
      ),
    );
  }

  Widget _buildItem(int index, IconData icon, String label) {
    final bool isSelected = selectedIndex == index;
    return GestureDetector(
      onTap: () => onItemSelected(index),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          NeumorphicContainer(
            padding: const EdgeInsets.all(12),
            borderRadius: 12,
            isInset: isSelected,
            child: Icon(
              icon,
              color: isSelected
                  ? const Color(0xFF3A86FF)
                  : const Color(0xFF8E949A),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: isSelected
                  ? const Color(0xFF3A86FF)
                  : const Color(0xFF8E949A),
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}

class NeumorphicTextField extends StatelessWidget {
  final String label;
  final String hint;
  final IconData icon;
  final bool isPassword;
  final Widget? trailing;
  final TextEditingController? controller;
  final TextInputType? keyboardType;

  const NeumorphicTextField({
    super.key,
    required this.label,
    required this.hint,
    required this.icon,
    this.isPassword = false,
    this.trailing,
    this.controller,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Color(0xFF8E949A),
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 12),
        NeumorphicContainer(
          isInset: true,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          borderRadius: 16,
          child: TextField(
            controller: controller,
            obscureText: isPassword,
            keyboardType: keyboardType,
            style: const TextStyle(fontSize: 14, color: Color(0xFF003566)),
            decoration: InputDecoration(
              border: InputBorder.none,
              hintText: hint,
              hintStyle: const TextStyle(
                color: Color(0xFF8E949A),
                fontSize: 14,
              ),
              icon: Icon(icon, color: const Color(0xFF3A86FF), size: 20),
              suffixIcon: trailing,
            ),
          ),
        ),
      ],
    );
  }
}
