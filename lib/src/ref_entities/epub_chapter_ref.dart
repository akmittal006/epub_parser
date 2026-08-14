import 'dart:async';

import 'package:quiver/collection.dart' as collections;
import 'package:quiver/core.dart';

import '../entities/epub_nav_section.dart';
import 'epub_text_content_file_ref.dart';

class EpubChapterRef {
  EpubTextContentFileRef? epubTextContentFileRef;

  String? Title;
  String? ContentFileName;
  String? Anchor;
  List<EpubChapterRef>? SubChapters;

  /// Navigation fragments that point inside this document, if any.
  ///
  /// Two or more of them mean the document holds several chapters, and it is
  /// split on those fragments when the book is read.
  List<EpubNavSection> NavSections = const <EpubNavSection>[];

  EpubChapterRef(EpubTextContentFileRef? epubTextContentFileRef) {
    this.epubTextContentFileRef = epubTextContentFileRef;
  }

  @override
  int get hashCode {
    var objects = [
      Title.hashCode,
      ContentFileName.hashCode,
      Anchor.hashCode,
      epubTextContentFileRef.hashCode,
      ...SubChapters?.map((subChapter) => subChapter.hashCode) ?? [0],
    ];
    return hashObjects(objects);
  }

  @override
  bool operator ==(other) {
    if (!(other is EpubChapterRef)) {
      return false;
    }
    return Title == other.Title &&
        ContentFileName == other.ContentFileName &&
        Anchor == other.Anchor &&
        epubTextContentFileRef == other.epubTextContentFileRef &&
        collections.listsEqual(SubChapters, other.SubChapters);
  }

  Future<String> readHtmlContent() async {
    return epubTextContentFileRef!.readContentAsText();
  }

  @override
  String toString() {
    return 'Title: $Title, Subchapter count: ${SubChapters!.length}';
  }
}
