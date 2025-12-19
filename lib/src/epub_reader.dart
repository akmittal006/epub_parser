import 'dart:async';

import 'package:archive/archive.dart';
import 'package:epub_parser/src/entities/epub_toc.dart';
import 'package:epub_parser/src/schema/navigation/epub_navigation_point.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart';

import 'entities/epub_book.dart';
import 'entities/epub_byte_content_file.dart';
import 'entities/epub_chapter.dart';
import 'entities/epub_content.dart';
import 'entities/epub_content_file.dart';
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

  static Future<List<EpubChapter>> readChapters(
      List<EpubChapterRef> chapterRefs) async {
    var result = <EpubChapter>[];
    await Future.forEach(chapterRefs, (EpubChapterRef chapterRef) async {
      var chapter = EpubChapter();
      chapter.ContentFileName = chapterRef.ContentFileName;
      chapter.Anchor = chapterRef.Anchor;
      chapter.HtmlContent = await chapterRef.readHtmlContent();

      var doc = chapter.HtmlContent == null ? dom.Document() : parse(chapter.HtmlContent);
      chapter.Title = chapterRef.Title;
      for (var node in doc.head?.children ?? []) {
        if (node != null && node.localName == 'title') {
          print("TITLE: " + node.localName);
          chapter.Title = node.text;
          break;
        }
      }
      chapter.Paragraphs = parseParagraphsFromDoc(doc);
      print('New EPUB_PARSER:  ${chapterRef.SubChapters!.length} for chap: ' +
          chapterRef.ContentFileName!);
      print('PARA LENGTH start:  ${chapter.Paragraphs.length} for chap: ' +
          chapterRef.ContentFileName!);
      // chapter.SubChapters = await readChapters(chapterRef.SubChapters!);
      // chapter.SubChapters?.forEach((subChapter) {
      //   chapter.Paragraphs.addAll(subChapter.Paragraphs);
      // });
      // await appendParagraphs(chapter);
      print('PARA LENGTH end :  ${chapter.Paragraphs.length} for chap: ' +
          chapterRef.ContentFileName!);

      result.add(chapter);
    });
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
    } on Exception catch (_, e) {}
    return [];
  }

  static List<dom.Element> parseParagraphs(String? htmlContent) {
    if (htmlContent == null) return [];
    try {
      var doc = parse(htmlContent);
      return _removeAllDiv(doc.getElementsByTagName('body').first.children);
    } on Exception catch (_, e) {}
    return [];
  }

  static Future<void> appendParagraphs(EpubChapter chapter) async {
    await Future.forEach(chapter.SubChapters as Iterable<EpubChapter>,
        (EpubChapter subChapter) async {
      var chapter = EpubChapter();
      chapter.Paragraphs.addAll(subChapter.Paragraphs);
    });
  }

  static Map<String, int>? mapPagesToChapter(List<EpubChapter>? chapters) {
    if (chapters == null) return null;
    var map = <String, int>{};
    for (var i = 0; i < chapters.length; i++) {
      var epubChapter = chapters[i];
      map[epubChapter.ContentFileName!] = i;
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

    points.forEach((point) {
      if (point.NavigationLabels == null) {
      } else {
        point.NavigationLabels?.forEach((label) {
          var item = ToCItem();
          if (book.PageToChapterMap!.containsKey(point.Content!.Source!.split('#')[0])) {
            item.chapterIndex =
            book.PageToChapterMap![point.Content!.Source!.split('#')[0]]!;
            item.label = prefix + label.Text!;
            result.add(item);
          }


          var items =
              traverseNavMap(book, point.ChildNavigationPoints, prefix + '  ');
          result.addAll(items as Iterable<ToCItem>);
        });
      }
    });
    return result;
  }
}
