import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'important_date.dart';
import 'important_date_service.dart';

class AddEditDateScreen extends StatefulWidget {
  final ImportantDate? existingDate;

  const AddEditDateScreen({super.key, this.existingDate});

  @override
  State<AddEditDateScreen> createState() => _AddEditDateScreenState();
}

class _AddEditDateScreenState extends State<AddEditDateScreen> {
  final _formKey = GlobalKey<FormState>();
  late String _title;
  late String _dateType;
  late DateTime _selectedDate;
  String? _note;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _title = widget.existingDate?.title ?? '';
    _dateType = widget.existingDate?.dateType ?? 'birthday';
    _selectedDate = widget.existingDate?.dateValue ?? DateTime.now();
    _note = widget.existingDate?.note;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(1970),
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppTheme.primaryTeal,
              surface: Color(0xFF1E293B),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    setState(() => _saving = true);
    if (widget.existingDate == null) {
      final created = await ImportantDateService.createDate(
        title: _title,
        dateType: _dateType,
        dateValue: _selectedDate,
        note: _note,
      );
      if (mounted) {
        setState(() => _saving = false);
        if (created != null) Navigator.pop(context, created);
      }
    } else {
      final updated = await ImportantDateService.updateDate(
        id: widget.existingDate!.id,
        title: _title,
        dateType: _dateType,
        dateValue: _selectedDate,
        note: _note,
      );
      if (mounted) {
        setState(() => _saving = false);
        if (updated != null) Navigator.pop(context, updated);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existingDate != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Edit Date 📅' : 'Add Important Date 📅', style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppTheme.primaryTeal,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                initialValue: _title,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Title / Event Name',
                  labelStyle: TextStyle(color: Colors.grey),
                  border: OutlineInputBorder(),
                ),
                validator: (val) => val == null || val.trim().isEmpty ? 'Please enter a title' : null,
                onSaved: (val) => _title = val!.trim(),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _dateType,
                dropdownColor: const Color(0xFF1E293B),
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Date Category',
                  labelStyle: TextStyle(color: Colors.grey),
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'birthday', child: Text('🎂 Birthday')),
                  DropdownMenuItem(value: 'anniversary', child: Text('💍 Anniversary')),
                  DropdownMenuItem(value: 'first_meeting', child: Text('❤️ First Meeting')),
                  DropdownMenuItem(value: 'custom', child: Text('✨ Custom Event')),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _dateType = val);
                },
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: const BorderSide(color: Colors.grey),
                ),
                title: const Text('Event Date', style: TextStyle(color: Colors.grey, fontSize: 12)),
                subtitle: Text(
                  '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}',
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                trailing: const Icon(Icons.calendar_month, color: AppTheme.primaryTeal),
                onTap: _pickDate,
              ),
              const SizedBox(height: 16),
              TextFormField(
                initialValue: _note,
                style: const TextStyle(color: Colors.white),
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Optional Note / Memory',
                  labelStyle: TextStyle(color: Colors.grey),
                  border: OutlineInputBorder(),
                ),
                onSaved: (val) => _note = val?.trim(),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryTeal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: _saving
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(isEdit ? 'Update Date' : 'Save Date', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
