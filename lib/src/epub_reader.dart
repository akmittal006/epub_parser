import 'dart:async';

import 'package:archive/archive.dart';
import 'package:am_epub_parser/src/entities/epub_toc.dart';
import 'package:am_epub_parser/src/schema/navigation/epub_navigation_point.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart';

import 'entities/epub_book.dart';
import 'entities/epub_byte_content_file.dart';
import 'entities/epub_chapter.dart';
import 'entities/epub_content.dart';
import 'entities/epub_content_file.dart';
import 'entities/epub_nav_section.dart';
import 'entities/epub_text_content_file.dart';
import 'readers/content_reader.dart';
import 'readers/schema_reader.dart';
import 'ref_entities/epub_book_ref.dart';
import 'ref_entities/epub_byte_content_file_ref.dart';
import 'ref_entities/epub_chapter_ref.dart';
import 'ref_entities/epub_content_file_ref.dart';
import 'ref_entities/epub_content_ref.dart';
import 'ref_entities/epub_text_content_file_ref.dart';
import 'schema/opf/epub_metadata_creator.dart';

/// A class that provides the primary interface to read Epub files.
///
/// To open an Epub and load all data at once use the [readBook()] method.
///
/// To open an Epub and load only basic metadata use the [openBook()] method.
/// This is a good option to quickly load text-based metadata, while leaving the
/// heavier lifting of loading images and main content for subsequent operations.
///
/// ## Example
/// ```dart
/// // Read the basic metadata.
/// EpubBookRef epub = await EpubReader.openBook(epubFileBytes);
/// // Extract values of interest.
/// String title = epub.Title;
/// String author = epub.Author;
/// var metadata = epub.Schema.Package.Metadata;
/// String genres = metadata.Subjects.join(', ');
/// ```
class EpubReader {
  /// Loads basics metadata.
  ///
  /// Opens the book asynchronously without reading its main content.
  /// Holds the handle to the EPUB file.
  ///
  /// Argument [bytes] should be the bytes of
  /// the epub file you have loaded with something like the [dart:io] package's
  /// [readAsBytes()].
  ///
  /// This is a fast and convenient way to get the most important information
  /// about the book, notably the [Title], [Author] and [AuthorList].
  /// Additional information is loaded in the [Schema] property such as the
  /// Epub version, Publishers, Languages and more.
  static Future<EpubBookRef> openBook(FutureOr<List<int>> bytes) async {
    List<int> loadedBytes;
    if (bytes is Future) {
      loadedBytes = await bytes;
    } else {
      loadedBytes = bytes;
    }

    var epubArchive = ZipDecoder().decodeBytes(loadedBytes);

    var bookRef = EpubBookRef(epubArchive);
    bookRef.Schema = await SchemaReader.readSchema(epubArchive);
    bookRef.Title = bookRef.Schema!.Package!.Metadata!.Titles!
        .firstWhere((String name) => true, orElse: () => '');
    bookRef.AuthorList = bookRef.Schema!.Package!.Metadata!.Creators!
        .map((EpubMetadataCreator creator) => creator.Creator)
        .toList();
    bookRef.Author = bookRef.AuthorList!.join(', ');
    bookRef.Content = ContentReader.parseContentMap(bookRef);
    return bookRef;
  }

  /// Opens the book asynchronously and reads all of its content into the memory. Does not hold the handle to the EPUB file.
  static Future<EpubBook> readBook(FutureOr<List<int>> bytes) async {
    var result = EpubBook();
    List<int> loadedBytes;
    if (bytes is Future) {
      loadedBytes = await bytes;
    } else {
      loadedBytes = bytes;
    }

    var epubBookRef = await openBook(loadedBytes);
    result.Schema = epubBookRef.Schema;
    result.Title = epubBookRef.Title;
    result.AuthorList = epubBookRef.AuthorList;
    result.Author = epubBookRef.Author;
    result.Content = await readContent(epubBookRef.Content!);
    result.CoverImage = await epubBookRef.readCoverAsUint8List();
    var chapterRefs = await epubBookRef.getChapters();
    result.Chapters = await readChapters(chapterRefs);
    result.PageToChapterMap = mapPagesToChapter(result.Chapters);
    result.Toc = readToC(result);
    result.ref = epubBookRef;
    return result;
  }

  static Future<EpubContent> readContent(EpubContentRef contentRef) async {
    var result = EpubContent();
    result.Html = await readTextContentFiles(contentRef.Html!);
    result.Css = await readTextContentFiles(contentRef.Css!);
    result.Images = await readByteContentFiles(contentRef.Images!);
    result.Fonts = await readByteContentFiles(contentRef.Fonts!);
    result.AllFiles = <String, EpubContentFile>{};

    result.Html!.forEach((String? key, EpubTextContentFile value) {
      result.AllFiles![key!] = value;
    });
    result.Css!.forEach((String? key, EpubTextContentFile value) {
      result.AllFiles![key!] = value;
    });

    result.Images!.forEach((String? key, EpubByteContentFile value) {
      result.AllFiles![key!] = value;
    });
    result.Fonts!.forEach((String? key, EpubByteContentFile value) {
      result.AllFiles![key!] = value;
    });

    await Future.forEach(contentRef.AllFiles!.keys, (dynamic key) async {
      if (!result.AllFiles!.containsKey(key)) {
        result.AllFiles![key] =
            await readByteContentFile(contentRef.AllFiles![key]!);
      }
    });

    return result;
  }

  static Future<Map<String, EpubTextContentFile>> readTextContentFiles(
      Map<String, EpubTextContentFileRef> textContentFileRefs) async {
    var result = <String, EpubTextContentFile>{};

    await Future.forEach(textContentFileRefs.keys, (dynamic key) async {
      EpubContentFileRef value = textContentFileRefs[key]!;
      var textContentFile = EpubTextContentFile();
      textContentFile.FileName = value.FileName;
      textContentFile.ContentType = value.ContentType;
      textContentFile.ContentMimeType = value.ContentMimeType;
      textContentFile.Content = await value.readContentAsText();
      result[key] = textContentFile;
    });
    return result;
  }

  static Future<Map<String, EpubByteContentFile>> readByteContentFiles(
      Map<String, EpubByteContentFileRef> byteContentFileRefs) async {
    var result = <String, EpubByteContentFile>{};
    await Future.forEach(byteContentFileRefs.keys, (dynamic key) async {
      result[key] = await readByteContentFile(byteContentFileRefs[key]!);
    });
    return result;
  }

  static Future<EpubByteContentFile> readByteContentFile(
      EpubContentFileRef contentFileRef) async {
    var result = EpubByteContentFile();

    result.FileName = contentFileRef.FileName;
    result.ContentType = contentFileRef.ContentType;
    result.ContentMimeType = contentFileRef.ContentMimeType;
    result.Content = await contentFileRef.readContentAsBytes();

    return result;
  }

  /// Reads every spine document into chapters.
  ///
  /// A document that the navigation addresses with two or more fragments holds
  /// several chapters (Project Gutenberg packs a whole book into a handful of
  /// documents), so it is split into one chapter per fragment. Every other
  /// document stays a single chapter, as the spine describes it.
  static Future<List<EpubChapter>> readChapters(
      List<EpubChapterRef> chapterRefs) async {
    var result = <EpubChapter>[];
    for (var chapterRef in chapterRefs) {
      var htmlContent = await chapterRef.readHtmlContent();
      var doc = parse(htmlContent);
      var documentTitle = _documentTitle(doc);
      var sections = _resolveNavSections(doc, chapterRef.NavSections);

      if (sections.length < 2) {
        var chapter = EpubChapter();
        chapter.ContentFileName = chapterRef.ContentFileName;
        chapter.Anchor = chapterRef.Anchor;
        chapter.HtmlContent = htmlContent;
        chapter.Title = documentTitle ?? chapterRef.Title;
        chapter.Paragraphs = parseParagraphsFromDoc(doc);
        chapter.SubChapters = <EpubChapter>[];
        result.add(chapter);
        continue;
      }

      result.addAll(
          _splitChapterByAnchors(chapterRef, doc, documentTitle, sections));
    }
    return result;
  }

  static String? _documentTitle(dom.Document doc) {
    for (var node in doc.head?.children ?? <dom.Element>[]) {
      if (node.localName == 'title') return node.text;
    }
    return null;
  }

  /// Navigation fragments that resolve to a top-level element of [doc]'s body,
  /// ordered by their position in the document and one per position.
  static List<_ResolvedNavSection> _resolveNavSections(
      dom.Document doc, List<EpubNavSection> navSections) {
    if (navSections.isEmpty) return const <_ResolvedNavSection>[];
    var body = doc.body;
    if (body == null) return const <_ResolvedNavSection>[];

    var indexById = _topLevelIndexById(body.children);
    var resolved = <_ResolvedNavSection>[];
    var seenAnchors = <String>{};
    for (var section in navSections) {
      if (!seenAnchors.add(section.anchor)) continue;
      var index = indexById[section.anchor];
      if (index == null) continue;
      resolved.add(_ResolvedNavSection(index, section.anchor, section.label));
    }
    resolved.sort((a, b) => a.startIndex.compareTo(b.startIndex));

    // Several fragments can land on the same top-level element; the first one
    // wins so that a chapter is never given an empty slice.
    var unique = <_ResolvedNavSection>[];
    for (var section in resolved) {
      if (unique.isNotEmpty && unique.last.startIndex == section.startIndex) {
        continue;
      }
      unique.add(section);
    }
    return unique;
  }

  /// Maps every id in the document body to the top-level element holding it.
  static Map<String, int> _topLevelIndexById(List<dom.Element> children) {
    var result = <String, int>{};
    for (var index = 0; index < children.length; index++) {
      _collectIds(children[index], index, result);
    }
    return result;
  }

  static void _collectIds(
      dom.Element element, int index, Map<String, int> sink) {
    var id = element.id;
    if (id.isNotEmpty) sink.putIfAbsent(id, () => index);
    for (var child in element.children) {
      _collectIds(child, index, sink);
    }
  }

  static List<EpubChapter> _splitChapterByAnchors(
      EpubChapterRef chapterRef,
      dom.Document doc,
      String? documentTitle,
      List<_ResolvedNavSection> sections) {
    var children = doc.body!.children;
    var headHtml = doc.head?.innerHtml ?? '';
    var result = <EpubChapter>[];

    void addSlice(int start, int end, String? anchor, String? title) {
      var slice = children.sublist(start, end);
      var paragraphs = _removeAllDiv(slice);
      if (paragraphs.isEmpty) return;
      var chapter = EpubChapter();
      chapter.ContentFileName = chapterRef.ContentFileName;
      chapter.Anchor = anchor;
      chapter.Title = title;
      chapter.HtmlContent = '<html><head>$headHtml</head><body>'
          '${slice.map((element) => element.outerHtml).join()}'
          '</body></html>';
      chapter.Paragraphs = paragraphs;
      chapter.SubChapters = <EpubChapter>[];
      result.add(chapter);
    }

    // Content ahead of the first fragment (cover art, publisher boilerplate)
    // stays a chapter of its own; it is dropped when there is none.
    addSlice(0, sections.first.startIndex, null, documentTitle);
    for (var index = 0; index < sections.length; index++) {
      var section = sections[index];
      var end = index + 1 < sections.length
          ? sections[index + 1].startIndex
          : children.length;
      addSlice(section.startIndex, end, section.anchor, section.label);
    }
    return result;
  }

  static List<dom.Element> _removeAllDiv(List<dom.Element> elements) {
    final result = <dom.Element>[];

    for (final node  in elements) {
      // var node = rawNode as dom.Element;
      if ((node.localName == 'div' || node.localName == 'section' || node.localName == 'article') &&
          node.children.isNotEmpty) {
        result.addAll(_removeAllDiv(node.children));
      } else {
        result.add(node);
      }
    }

    return result;
  }

  static List<dom.Element> parseParagraphsFromDoc(dom.Document doc) {
    if (doc.getElementsByTagName('body').isEmpty) return [];
    try {
      // var doc = parse(htmlContent);
      return _removeAllDiv(doc.getElementsByTagName('body').first.children);
    } on Exception catch (_) {}
    return [];
  }

  static List<dom.Element> parseParagraphs(String? htmlContent) {
    if (htmlContent == null) return [];
    try {
      var doc = parse(htmlContent);
      return _removeAllDiv(doc.getElementsByTagName('body').first.children);
    } on Exception catch (_) {}
    return [];
  }

  static Future<void> appendParagraphs(EpubChapter chapter) async {
    await Future.forEach(chapter.SubChapters as Iterable<EpubChapter>,
        (EpubChapter subChapter) async {
      var chapter = EpubChapter();
      chapter.Paragraphs.addAll(subChapter.Paragraphs);
    });
  }

  /// Maps a navigation target onto the chapter that holds it.
  ///
  /// Documents split on fragments contribute one `file.xhtml#anchor` key per
  /// chapter; the plain file name always resolves to the first chapter read
  /// from that document.
  static Map<String, int>? mapPagesToChapter(List<EpubChapter>? chapters) {
    if (chapters == null) return null;
    var map = <String, int>{};
    for (var i = 0; i < chapters.length; i++) {
      var epubChapter = chapters[i];
      var fileName = epubChapter.ContentFileName;
      if (fileName == null) continue;
      map.putIfAbsent(fileName, () => i);
      var anchor = epubChapter.Anchor;
      if (anchor != null && anchor.isNotEmpty) {
        map['$fileName#$anchor'] = i;
      }
    }
    return map;
  }

  static TableOfContents? readToC(EpubBook book) {
    if (book.Chapters == null) return null;
    var toc = TableOfContents();
    toc.toc = traverseNavMap(book, book.Schema!.Navigation!.NavMap!.Points, '');
    return toc;
  }

  static List<ToCItem> traverseNavMap(
      EpubBook book, List<EpubNavigationPoint>? points, String prefix) {
    var result = <ToCItem>[];
    if (points == null) return result;

    var pageToChapter = book.PageToChapterMap ?? const <String, int>{};
    points.forEach((point) {
      var source = point.Content?.Source;
      var label = point.NavigationLabels?.isNotEmpty == true
          ? point.NavigationLabels!.first.Text
          : null;
      if (source != null && label != null) {
        var target = Uri.decodeFull(source);
        // A fragment resolves to its own chapter once the document holding it
        // has been split; otherwise the whole document is the target.
        var chapterIndex =
            pageToChapter[target] ?? pageToChapter[target.split('#')[0]];
        if (chapterIndex != null) {
          var item = ToCItem();
          item.chapterIndex = chapterIndex;
          item.label = prefix + label;
          result.add(item);
        }
      }
      result.addAll(
          traverseNavMap(book, point.ChildNavigationPoints, prefix + '  '));
    });
    return result;
  }
}

/// A navigation fragment located inside a parsed document.
class _ResolvedNavSection {
  const _ResolvedNavSection(this.startIndex, this.anchor, this.label);

  /// Index of the top-level body element the fragment points at.
  final int startIndex;
  final String anchor;
  final String label;
}
