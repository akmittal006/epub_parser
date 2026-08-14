import 'package:archive/archive.dart';

/// A navigation entry: a label and the `file#fragment` it addresses.
class FixtureNavPoint {
  const FixtureNavPoint(this.label, this.source);

  final String label;
  final String source;
}

String fixtureDocument({required String title, required String body}) =>
    '<?xml version="1.0" encoding="utf-8"?>'
    '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>$title</title>'
    '</head><body>$body</body></html>';

/// Builds a minimal but complete EPUB from documents, a spine and a navMap.
List<int> buildEpubFixture({
  required Map<String, String> documents,
  required List<String> spine,
  required List<FixtureNavPoint> navPoints,
}) {
  final manifest = StringBuffer()
    ..write('<item href="toc.ncx" id="ncx" '
        'media-type="application/x-dtbncx+xml"/>');
  var idIndex = 0;
  final idsByHref = <String, String>{};
  for (final href in documents.keys) {
    final id = 'doc${idIndex++}';
    idsByHref[href] = id;
    manifest.write('<item href="$href" id="$id" '
        'media-type="application/xhtml+xml"/>');
  }

  final spineItems =
      spine.map((href) => '<itemref idref="${idsByHref[href]}"/>').join();

  final navMap = StringBuffer();
  for (var index = 0; index < navPoints.length; index++) {
    final point = navPoints[index];
    navMap.write('<navPoint id="np$index" playOrder="${index + 1}">'
        '<navLabel><text>${point.label}</text></navLabel>'
        '<content src="${point.source}"/>'
        '</navPoint>');
  }

  final files = <String, String>{
    'META-INF/container.xml': '<?xml version="1.0"?><container version="1.0" '
        'xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
        '<rootfiles><rootfile full-path="OEBPS/content.opf" '
        'media-type="application/oebps-package+xml"/></rootfiles></container>',
    'OEBPS/content.opf': '<?xml version="1.0" encoding="utf-8"?>'
        '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" '
        'unique-identifier="id">'
        '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
        '<dc:identifier id="id">fixture</dc:identifier>'
        '<dc:title>Fixture Book</dc:title>'
        '<dc:language>en</dc:language>'
        '<dc:creator>Fixture Author</dc:creator>'
        '</metadata>'
        '<manifest>$manifest</manifest>'
        '<spine toc="ncx">$spineItems</spine>'
        '</package>',
    'OEBPS/toc.ncx': '<?xml version="1.0" encoding="utf-8"?>'
        '<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">'
        '<head><meta name="dtb:uid" content="fixture"/></head>'
        '<docTitle><text>Fixture Book</text></docTitle>'
        '<navMap>$navMap</navMap></ncx>',
    for (final entry in documents.entries) 'OEBPS/${entry.key}': entry.value,
  };

  final archive = Archive()
    ..addFile(ArchiveFile.string('mimetype', 'application/epub+zip'));
  files.forEach((path, contents) {
    archive.addFile(ArchiveFile.string(path, contents));
  });
  return ZipEncoder().encode(archive)!;
}
