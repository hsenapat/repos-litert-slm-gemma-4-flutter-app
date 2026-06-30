class RagChunk {
  final String text;
  final String source;
  final int page;
  final double score;

  const RagChunk({
    required this.text,
    required this.source,
    required this.page,
    required this.score,
  });
}
