import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'shared_note.dart';
import 'shared_notes_service.dart';

class AddEditNoteScreen extends StatefulWidget {
  final SharedNote? existingNote;

  const AddEditNoteScreen({super.key, this.existingNote});

  @override
  State<AddEditNoteScreen> createState() => _AddEditNoteScreenState();
}

class _AddEditNoteScreenState extends State<AddEditNoteScreen> {
  final _formKey = GlobalKey<FormState>();
  late String _title;
  late String _content;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _title = widget.existingNote?.title ?? '';
    _content = widget.existingNote?.content ?? '';
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    setState(() => _saving = true);
    if (widget.existingNote == null) {
      final created = await SharedNotesService.createNote(
        title: _title,
        content: _content,
      );
      if (mounted) {
        setState(() => _saving = false);
        if (created != null) Navigator.pop(context, created);
      }
    } else {
      final updated = await SharedNotesService.updateNote(
        id: widget.existingNote!.id,
        title: _title,
        content: _content,
      );
      if (mounted) {
        setState(() => _saving = false);
        if (updated != null) Navigator.pop(context, updated);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existingNote != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Edit Note 📝' : 'New Shared Note 📝', style: const TextStyle(fontWeight: FontWeight.bold)),
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
                  labelText: 'Title',
                  labelStyle: TextStyle(color: Colors.grey),
                  border: OutlineInputBorder(),
                ),
                validator: (val) => val == null || val.trim().isEmpty ? 'Please enter a title' : null,
                onSaved: (val) => _title = val!.trim(),
              ),
              const SizedBox(height: 16),
              TextFormField(
                initialValue: _content,
                style: const TextStyle(color: Colors.white),
                maxLines: 10,
                decoration: const InputDecoration(
                  labelText: 'Note Content',
                  labelStyle: TextStyle(color: Colors.grey),
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
                validator: (val) => val == null || val.trim().isEmpty ? 'Please enter note content' : null,
                onSaved: (val) => _content = val!.trim(),
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
                    : Text(isEdit ? 'Update Note' : 'Save Note', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
