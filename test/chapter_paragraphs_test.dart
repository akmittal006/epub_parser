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

  group('an inline element around blocks', () {
    List<String> roundTrip(String source) {
      final first = EpubReader.parseParagraphs(source);
      final again = EpubReader.parseParagraphs(
        '<body>${first.map((element) => element.outerHtml).join()}</body>',
      );
      expect(
        again.map((element) => element.outerHtml),
        first.map((element) => element.outerHtml),
        reason: 'stored paragraphs must read back into themselves',
      );
      return first.map((element) => element.outerHtml).toList();
    }

    test('a link around divs carries into each paragraph', () {
      expect(
        roundTrip('<body><a href="next.xhtml"><div>Alpha.</div>'
            '<div>Beta.</div></a><p>After.</p></body>'),
        [
          '<div><a href="next.xhtml">Alpha.</a></div>',
          '<div><a href="next.xhtml">Beta.</a></div>',
          '<p>After.</p>',
        ],
      );
    });

    test('a span around paragraphs carries into each paragraph', () {
      expect(
        roundTrip('<body><span class="x"><p>Alpha.</p><p>Beta.</p></span>'
            '</body>'),
        [
          '<p><span class="x">Alpha.</span></p>',
          '<p><span class="x">Beta.</span></p>',
        ],
      );
    });

    test('text around the blocks keeps the wrapper too', () {
      expect(
        roundTrip('<body><div>Before <em id="e">lead <div>Middle.</div> tail'
            '</em> after.</div></body>'),
        [
          '<p>Before </p>',
          '<p><em>lead </em></p>',
          '<div><em>Middle.</em></div>',
          '<p><em> tail</em></p>',
          '<p> after.</p>',
        ],
      );
    });

    test('a block with structure of its own keeps it', () {
      expect(
        roundTrip('<body><a href="x"><ul><li>One</li></ul></a></body>'),
        ['<ul><li>One</li></ul>'],
      );
    });
  });

  group('a table', () {
    test('is read row by row, with headers and caption', () {
      final paragraphs = EpubReader.parseParagraphs(
        '<body><table><caption>Prices</caption>'
        '<thead><tr><th>Item</th><th>Cost</th></tr></thead>'
        '<tbody><tr><td>Bread</td><td><em>2</em></td></tr>'
        '<tr><td>Milk</td><td></td></tr></tbody></table>'
        '<p>After.</p></body>',
      );
      expect(paragraphs.map(text), [
        'Prices',
        'Item, Cost',
        'Bread, 2',
        'Milk',
        'After.',
      ]);
    });

    test('nested in a cell follows the row that holds it', () {
      final paragraphs = EpubReader.parseParagraphs(
        '<body><table><tr><td>Outer</td><td>Cell'
        '<table><tr><td>Inner one</td></tr><tr><td>Inner two</td></tr>'
        '</table></td></tr><tr><td>Last row</td></tr></table></body>',
      );
      expect(paragraphs.map(text), [
        'Outer, Cell',
        'Inner one',
        'Inner two',
        'Last row',
      ]);
    });

    test('reads back into the same rows', () {
      final first = EpubReader.parseParagraphs(
        '<body><table><tr><td>Alpha.</td></tr><tr><td>Beta.</td></tr>'
        '</table><p>After.</p></body>',
      );
      final again = EpubReader.parseParagraphs(
        '<body>${first.map((element) => element.outerHtml).join()}</body>',
      );
      expect(first.map(text), ['Alpha.', 'Beta.', 'After.']);
      expect(
        again.map((element) => element.outerHtml),
        first.map((element) => element.outerHtml),
      );
    });
  });
}
