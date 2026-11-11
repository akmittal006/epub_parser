import 'package:am_epub_parser/am_epub_parser.dart';
import 'package:html/parser.dart' show parse;
import 'package:test/test.dart';

/// Project Gutenberg's "O Primo Bazilio" (ebook 42942) writes its body as bare
/// text directly inside a `<div>`, one paragraph per `<br/>`. Every run of text
/// is a paragraph, in document order, with its inline markup kept.
void main() {
  String text(element) =>
      element.text.replaceAll(RegExp(r'\s+'), ' ').trim() as String;

  test('bare text in a container splits at <br> and keeps its markup', () {
    final paragraphs = EpubReader.parseParagraphs(
      '<body><div><div class="poetry2">\n'
      'Amici, la notte é bella,<br/>\n'
      'La luna va spontari...</div>\n'
      '<br/>\n<br/>\n'
      '—Fica tão só, coitada!...—disse Jorge. <br/>\n<br/>\n'
      'Sebastião coçou a barba em silencio—e a voz\n'
      'nos <em>altos</em> da melodia : <br/>\n<br/>\n'
      '<p>A paragraph of its own.</p>\n'
      'Era uma tristeza secreta de Jorge.</div></body>',
    );

    expect(paragraphs.map(text), [
      'Amici, la notte é bella,',
      'La luna va spontari...',
      '—Fica tão só, coitada!...—disse Jorge.',
      'Sebastião coçou a barba em silencio—e a voz nos altos da melodia :',
      'A paragraph of its own.',
      'Era uma tristeza secreta de Jorge.',
    ]);
    expect(paragraphs[3].querySelector('em')?.text, 'altos');
  });

  test('a container that is one run is its own paragraph', () {
    final paragraphs = EpubReader.parseParagraphs(
      '<body><div class="figcenter"><a id="fill5"></a><img src="a.png"/></div>'
      '<div class="note">One <em>whole</em> note.</div>'
      '<div><a id="empty"></a></div></body>',
    );

    expect(paragraphs.map((element) => element.localName), ['div', 'div']);
    expect(paragraphs[0].querySelector('img'), isNotNull);
    expect(text(paragraphs[1]), 'One whole note.');
  });

  test('the paragraphs read back into themselves', () {
    final first = EpubReader.parseParagraphs(
      '<body><div>Bare <em>text</em><br/>more text'
      '<div class="poetry2">Verse<br/>lines</div><h2>II</h2>'
      '<div class="note">One note.</div></div></body>',
    );
    final again = EpubReader.parseParagraphs(
      '<body>${first.map((element) => element.outerHtml).join()}</body>',
    );

    expect(
      again.map((element) => element.outerHtml),
      first.map((element) => element.outerHtml),
    );
  });

  test('script, style, template and noscript are never reader text', () {
    const source = '<body><h2>Chapter</h2>'
        '<script>var telemetry = 42;</script>'
        '<style>.note { display:none }</style>'
        '<p>Story<script>track();</script> goes on.</p>'
        '<div>Bare <noscript>Enable JS</noscript>text.<br/>'
        '<template><p>Hidden</p></template>More.</div></body>';
    final paragraphs = EpubReader.parseParagraphs(source);

    expect(paragraphs.map(text), [
      'Chapter',
      'Story goes on.',
      'Bare text.',
      'More.',
    ]);
    for (final paragraph in paragraphs) {
      expect(paragraph.querySelector('script,style,template,noscript'), isNull);
    }

    final again = EpubReader.parseParagraphs(
      '<body>${paragraphs.map((element) => element.outerHtml).join()}</body>',
    );
    expect(
      again.map((element) => element.outerHtml),
      paragraphs.map((element) => element.outerHtml),
    );
  });

  test('a chapter document keeps its own scripts in its HTML', () {
    final document =
        parse('<body><p>Story<script>track();</script></p></body>');
    EpubReader.parseParagraphsFromDoc(document);
    expect(document.querySelector('script'), isNotNull);
  });
}
