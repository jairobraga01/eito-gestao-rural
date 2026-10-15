import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../dados/db.dart';
import '../util/util.dart';

/// Foto do animal na ficha. Tocar tira ou troca a foto (câmera ou galeria).
class FotoAnimal extends StatefulWidget {
  const FotoAnimal({super.key, required this.animalId});
  final int animalId;

  @override
  State<FotoAnimal> createState() => _FotoAnimalState();
}

class _FotoAnimalState extends State<FotoAnimal> {
  late Future<String?> _foto = Db.foto(widget.animalId);

  Future<void> _trocar(bool temFoto) async {
    final op = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Tirar foto'),
              onTap: () => Navigator.pop(c, 'camera')),
          ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Escolher da galeria'),
              onTap: () => Navigator.pop(c, 'galeria')),
          if (temFoto)
            ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Remover foto'),
                onTap: () => Navigator.pop(c, 'remover')),
        ]),
      ),
    );
    if (op == null) return;
    String? b64;
    if (op != 'remover') {
      // Foto pequena: cabe no banco e funciona sem sinal.
      final img = await ImagePicker().pickImage(
        source: op == 'camera' ? ImageSource.camera : ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 70,
      );
      if (img == null) return;
      final bytes = await img.readAsBytes();
      if (bytes.length > 700 * 1024) {
        if (mounted) avisar(context, 'Foto grande demais. Tente de novo mais de longe ou com menos luz.');
        return;
      }
      b64 = base64Encode(bytes);
    }
    await Db.salvarFoto(widget.animalId, b64);
    if (mounted) setState(() => _foto = Future.value(b64));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FutureBuilder<String?>(
      future: _foto,
      builder: (context, s) {
        final b64 = s.data;
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Material(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => _trocar(b64 != null),
              child: SizedBox(
                height: 220,
                width: double.infinity,
                child: b64 == null
                    ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.add_a_photo_outlined, size: 48, color: cs.primary),
                        const SizedBox(height: 8),
                        Text(s.connectionState == ConnectionState.done ? 'Tocar para pôr a foto' : 'Carregando foto…'),
                      ])
                    : Image.memory(base64Decode(b64), fit: BoxFit.cover, gaplessPlayback: true),
              ),
            ),
          ),
        );
      },
    );
  }
}
