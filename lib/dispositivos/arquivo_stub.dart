/// Fora do navegador não há download de arquivo.
bool baixarArquivo(String nome, String conteudo, {String tipo = 'text/plain'}) => false;

/// Fora do navegador não há escolha de arquivo.
Future<String?> escolherArquivoTexto({String aceitar = '.json'}) async => null;

/// Fora do navegador não há impressão.
bool imprimirHtml(String html) => false;
