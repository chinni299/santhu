import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'couple_status.dart';

class CoupleStatusPicker extends StatefulWidget {
  final CoupleStatusType initialType;
  final String? initialCustomText;
  final Function(CoupleStatusType type, String? customText) onSelected;

  const CoupleStatusPicker({
    super.key,
    required this.initialType,
    this.initialCustomText,
    required this.onSelected,
  });

  @override
  State<CoupleStatusPicker> createState() => _CoupleStatusPickerState();
}

class _CoupleStatusPickerState extends State<CoupleStatusPicker> {
  late CoupleStatusType _selectedType;
  final _textController = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    _selectedType = widget.initialType;
    if (widget.initialCustomText != null) {
      _textController.text = widget.initialCustomText!;
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_selectedType == CoupleStatusType.custom) {
      final trimmed = _textController.text.trim();
      if (trimmed.isEmpty) {
        setState(() => _error = 'Custom status cannot be empty');
        return;
      }
      widget.onSelected(_selectedType, trimmed);
    } else {
      widget.onSelected(_selectedType, null);
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF1E293B)
            : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Set Couple Status',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 16),
            ...CoupleStatusType.values.map((type) {
              final isSelected = type == _selectedType;
              return ListTile(
                leading: Text(type.emoji, style: const TextStyle(fontSize: 20)),
                title: Text(type.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                trailing: isSelected ? const Icon(Icons.check_circle_rounded, color: AppTheme.primaryTeal) : null,
                onTap: () {
                  setState(() {
                    _selectedType = type;
                    _error = null;
                  });
                },
              );
            }),
            if (_selectedType == CoupleStatusType.custom) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _textController,
                maxLength: 30,
                decoration: InputDecoration(
                  labelText: 'Custom Status',
                  hintText: 'e.g. Cooking dinner 🍳',
                  errorText: _error,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryTeal,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _submit,
                child: const Text('Save Status', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
