import 'package:am_epub_parser/am_epub_parser.dart';
import 'package:am_epub_parser/src/utils/xhtml_normalizer.dart';
import 'package:test/test.dart';

import 'epub_fixture.dart';

/// Project Gutenberg writes two chapter shapes, and a chapter slice has to keep
/// its own heading in both.
///
/// * wrapper anchor: `<div class="chapter" id="chap01"><h2>CHAPTER I</h2>…`
/// * nested anchor:  `<h2 id="pgepubid01"><a id="chap01"/>CHAPTER I</h2>`
///
/// The nested form writes the anchor in the XHTML self-closing form. An HTML5
/// tree builder ignores the solidus, so the anchor is never closed; because `a`
/// is a formatting element, the first character token after `</h2>` - the
/// newline every Gutenberg document puts between its blocks - re-creates the
/// anchor as a sibling, and every following element is inserted inside it. The
/// rest of the chapter collapses into that one anchor, and any heading it
/// swallows stops being a chapter start. The fixtures below keep those
/// newlines, because without them the shape does not reproduce.
void main() {
  group('normalizeSelfClosingTags', () {
    test('writes out the end tag of a non-void element', () {
      expect(normalizeSelfClosingTags('<a id="chap01"/>Chapter'),
          '<a id="chap01"></a>Chapter');
      expect(normalizeSelfClosingTags('<div class="chapter" />'),
          '<div class="chapter" ></div>');
    });

    test('leaves void elements alone', () {
      const markup = '<br/><hr/><img src="i.png"/><meta charset="utf-8"/>'
          '<link rel="stylesheet" href="0.css"/>';
      expect(normalizeSelfClosingTags(markup), markup);
    });

    test('does not end a tag early on a slash inside an attribute', () {
      expect(
        normalizeSelfClosingTags('<a href="http://x/y"/>text'),
        '<a href="http://x/y"></a>text',
      );
    });

    test('leaves markup that closes its own tags untouched', () {
      const markup = '<h2 id="chap01"><a id="a1"></a>CHAPTER I</h2><p>Body.</p>';
      expect(normalizeSelfClosingTags(markup), markup);
    });
  });

  group('a chapter slice keeps the heading that carries its anchor', () {
    test('wrapper anchor: the heading sits inside the addressed element',
        () async {
      final book = await EpubReader.readBook(_wrapperAnchorFixture());
      final chapters = book.Chapters!;

      expect(chapters.map((chapter) => chapter.Title),
          ['CHAPTER I', 'CHAPTER II', 'CHAPTER III']);
      _expectChapterOpensWithItsHeading(chapters[0], 'CHAPTER I');
      _expectChapterOpensWithItsHeading(chapters[1], 'CHAPTER II');
      _expectChapterOpensWithItsHeading(chapters[2], 'CHAPTER III');
      expect(_textOf(chapters[0]), contains('First chapter body.'));
      expect(_textOf(chapters[0]), isNot(contains('Second chapter body.')));
    });

    test('nested self-closing anchor: the heading carries the anchor',
        () async {
      final book = await EpubReader.readBook(_nestedAnchorFixture());
      final chapters = book.Chapters!;

      // The pre-fragment boilerplate, then one chapter per fragment.
      expect(chapters.map((chapter) => chapter.Title), [
        'The Project Gutenberg eBook of Fixture Book',
        'CHAPTER I',
        'CHAPTER II',
        'CHAPTER III',
      ]);
      _expectChapterOpensWithItsHeading(chapters[1], 'CHAPTER I');
      _expectChapterOpensWithItsHeading(chapters[2], 'CHAPTER II');
      _expectChapterOpensWithItsHeading(chapters[3], 'CHAPTER III');

      // The unclosed anchor used to swallow every following element into one
      // paragraph; each chapter keeps its own body, and only its own.
      expect(chapters[1].Paragraphs, hasLength(3));
      expect(_textOf(chapters[1]), contains('First chapter body.'));
      expect(_textOf(chapters[1]), contains('Still the first chapter.'));
      expect(_textOf(chapters[1]), isNot(contains('Second chapter body.')));
      expect(chapters[1].HtmlContent, contains('First chapter body.'));
      expect(
          chapters[1].HtmlContent, isNot(contains('Second chapter body.')));
    });

    test('a heading that follows a self-closing anchor stays a chapter start',
        () async {
      // The Gutenberg illustration shape: the anchor is a bare marker, and the
      // navigation addresses the heading that follows it.
      final book = await EpubReader.readBook(_captionAnchorFixture());
      final chapters = book.Chapters!;

      expect(chapters.map((chapter) => chapter.Title),
          ['The Project Gutenberg eBook of Fixture Book', 'Caption', 'CHAPTER I']);
      _expectChapterOpensWithItsHeading(chapters[1], 'Caption');
      _expectChapterOpensWithItsHeading(chapters[2], 'CHAPTER I');
      expect(_textOf(chapters[1]), contains('Caption body.'));
      expect(_textOf(chapters[1]), isNot(contains('First chapter body.')));
    });

    test('two fragments behind one self-closing anchor are two chapters',
        () async {
      // Previously both fragments resolved to the single re-created anchor, so
      // one of them was dropped and its heading went with it.
      final book = await EpubReader.readBook(_twoFragmentsFixture());
      final chapters = book.Chapters!;

      expect(chapters.map((chapter) => chapter.Title),
          ['The Project Gutenberg eBook of Fixture Book', 'Illustration', 'Contents']);
      _expectChapterOpensWithItsHeading(chapters[1], 'Illustration');
      _expectChapterOpensWithItsHeading(chapters[2], 'Contents');
    });
  });

  group('a document that is a chapter on its own', () {
    test('is named by the navigation, not by the book title', () async {
      final book = await EpubReader.readBook(_documentPerChapterFixture());
      final chapters = book.Chapters!;

      expect(chapters.map((chapter) => chapter.Title),
          ['Cover', 'CHAPTER I', 'CHAPTER II']);
      _expectChapterOpensWithItsHeading(chapters[1], 'CHAPTER I');
      _expectChapterOpensWithItsHeading(chapters[2], 'CHAPTER II');
      expect(book.Toc!.toc.map((item) => item.chapterIndex), [0, 1, 2]);
    });

    test('falls back to its document title when nothing addresses it',
        () async {
      final book = await EpubReader.readBook(buildEpubFixture(
        documents: {
          'part0000.xhtml':
              fixtureDocument(title: 'Only Document', body: '<p>Body.</p>'),
        },
        spine: const ['part0000.xhtml'],
        navPoints: const [],
      ));

      expect(book.Chapters!.single.Title, 'Only Document');
    });
  });
}

/// Every chapter opens with its own heading, and carries it exactly once.
void _expectChapterOpensWithItsHeading(EpubChapter chapter, String heading) {
  final headings = chapter.Paragraphs
      .where((element) => RegExp(r'^h[1-6]$').hasMatch(element.localName ?? ''))
      .map((element) => element.text.trim())
      .toList();
  expect(headings.where((text) => text == heading), hasLength(1),
      reason: 'chapter "${chapter.Title}" should carry "$heading" once');
  expect(chapter.Paragraphs.first.text.trim(), heading,
      reason: 'chapter "${chapter.Title}" should open with "$heading"');
}

String _textOf(EpubChapter chapter) =>
    chapter.Paragraphs.map((element) => element.text).join(' ');

/// `<div class="chapter" id="…"><h2>…</h2>` - the shape that always worked.
List<int> _wrapperAnchorFixture() => buildEpubFixture(
      documents: {
        'book-0.xhtml': fixtureDocument(
          title: 'The Project Gutenberg eBook of Fixture Book',
          body: '<div class="chapter" id="chap01">\n'
              '<h2>CHAPTER I</h2>\n<p>First chapter body.</p>\n</div>\n'
              '<div class="chapter" id="chap02">\n'
              '<h2>CHAPTER II</h2>\n<p>Second chapter body.</p>\n</div>\n'
              '<div class="chapter" id="chap03">\n'
              '<h2>CHAPTER III</h2>\n<p>Third chapter body.</p>\n</div>\n',
        ),
      },
      spine: const ['book-0.xhtml'],
      navPoints: const [
        FixtureNavPoint('CHAPTER I', 'book-0.xhtml#chap01'),
        FixtureNavPoint('CHAPTER II', 'book-0.xhtml#chap02'),
        FixtureNavPoint('CHAPTER III', 'book-0.xhtml#chap03'),
      ],
    );

/// `<h2 id="…"><a id="…"/>…</h2>` - the anchor nested in the heading, written
/// in the XHTML self-closing form.
List<int> _nestedAnchorFixture() => buildEpubFixture(
      documents: {
        'book-0.xhtml': fixtureDocument(
          title: 'The Project Gutenberg eBook of Fixture Book',
          body: '<header id="pg-header"><p>Boilerplate</p></header>\n'
              '<h2 id="pgepubid01"><a id="chap01"/> CHAPTER I</h2>\n'
              '<p>First chapter body.</p>\n'
              '<p>Still the first chapter.</p>\n'
              '<h2 id="pgepubid02"><a id="chap02"/> CHAPTER II</h2>\n'
              '<p>Second chapter body.</p>\n'
              '<h2 id="pgepubid03"><a id="chap03"/> CHAPTER III</h2>\n'
              '<p>Third chapter body.</p>\n',
        ),
      },
      spine: const ['book-0.xhtml'],
      navPoints: const [
        FixtureNavPoint('CHAPTER I', 'book-0.xhtml#pgepubid01'),
        FixtureNavPoint('CHAPTER II', 'book-0.xhtml#pgepubid02'),
        FixtureNavPoint('CHAPTER III', 'book-0.xhtml#pgepubid03'),
      ],
    );

/// A bare `<a id="…"/>` marker followed by the addressed heading.
List<int> _captionAnchorFixture() => buildEpubFixture(
      documents: {
        'book-0.xhtml': fixtureDocument(
          title: 'The Project Gutenberg eBook of Fixture Book',
          body: '<div class="figure"><a id="i007"/><img src="i007.jpg"/></div>\n'
              '<h3 id="pgepubid06">Caption</h3>\n'
              '<p>Caption body.</p>\n'
              '<h2 id="pgepubid11"><a id="chap01"/> CHAPTER I</h2>\n'
              '<p>First chapter body.</p>\n',
        ),
      },
      spine: const ['book-0.xhtml'],
      navPoints: const [
        FixtureNavPoint('Caption', 'book-0.xhtml#pgepubid06'),
        FixtureNavPoint('CHAPTER I', 'book-0.xhtml#pgepubid11'),
      ],
    );

/// Two navigation fragments that the re-created anchor used to merge into one.
List<int> _twoFragmentsFixture() => buildEpubFixture(
      documents: {
        'book-0.xhtml': fixtureDocument(
          title: 'The Project Gutenberg eBook of Fixture Book',
          body: '<div class="figure"><a id="i007"/><img src="i007.jpg"/></div>\n'
              '<h3 id="pgepubid06">Illustration</h3>\n'
              '<h2 id="pgepubid07">Contents</h2>\n'
              '<p>Chapter list.</p>\n',
        ),
      },
      spine: const ['book-0.xhtml'],
      navPoints: const [
        FixtureNavPoint('Illustration', 'book-0.xhtml#pgepubid06'),
        FixtureNavPoint('Contents', 'book-0.xhtml#pgepubid07'),
      ],
    );

/// One chapter per spine document, each addressed by a fragment.
List<int> _documentPerChapterFixture() => buildEpubFixture(
      documents: {
        'part0000.xhtml': fixtureDocument(
          title: 'The Project Gutenberg eBook of Fixture Book',
          body: '<div class="cover" id="cover"><p>Cover art</p></div>',
        ),
        'part0001.xhtml': fixtureDocument(
          title: 'The Project Gutenberg eBook of Fixture Book',
          body: '<div class="chapter" id="pgepubid01">\n'
              '<h2><a id="chap01"/> CHAPTER I</h2>\n'
              '<p>First chapter body.</p>\n'
              '<p>Still the first chapter.</p>\n</div>\n',
        ),
        'part0002.xhtml': fixtureDocument(
          title: 'The Project Gutenberg eBook of Fixture Book',
          body: '<div class="chapter" id="pgepubid02">\n'
              '<h2><a id="chap02"/> CHAPTER II</h2>\n'
              '<p>Second chapter body.</p>\n</div>\n',
        ),
      },
      spine: const ['part0000.xhtml', 'part0001.xhtml', 'part0002.xhtml'],
      navPoints: const [
        FixtureNavPoint('Cover', 'part0000.xhtml#cover'),
        FixtureNavPoint('CHAPTER I', 'part0001.xhtml#pgepubid01'),
        FixtureNavPoint('CHAPTER II', 'part0002.xhtml#pgepubid02'),
      ],
    );
